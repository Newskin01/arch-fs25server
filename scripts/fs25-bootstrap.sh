#!/bin/bash
set -euo pipefail


log_stage="bootstrap-start"
cleanup_trap() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "[fs25-bootstrap] $(date --iso-8601=seconds) error at stage=${log_stage} status=${status}" >&2
  fi
}
trap cleanup_trap EXIT

LOG_FILE=""
PATCH_ID="${FS25_PATCH_ID:-unknown}"

log() {
  local ts
  ts=$(date --iso-8601=seconds)
  local line="[fs25-bootstrap] ${ts} $*"
  if [[ -n "${LOG_FILE}" ]]; then
    echo "${line}" >>"${LOG_FILE}"
  fi
  echo "${line}"
}

require_secret_value() {
  local name="$1"
  local value="$2"
  local min_len="$3"
  local disallowed="$4"
  if [[ -z "${value}" ]]; then
    log "Fatal: ${name} must be set and cannot be empty. Set ALLOW_DEFAULT_PASSWORDS=yes to bypass (not recommended)."
    exit 1
  fi
  if [[ -n "${disallowed}" && "${value}" == "${disallowed}" ]]; then
    log "Fatal: ${name} is still using the insecure default '${disallowed}'."
    exit 1
  fi
  if (( min_len > 0 )) && ((${#value} < min_len)); then
    log "Fatal: ${name} must be at least ${min_len} characters long."
    exit 1
  fi
}

enforce_required_credentials() {
  local allow_defaults="${ALLOW_DEFAULT_PASSWORDS:-no}"
  if [[ "${allow_defaults,,}" == "yes" ]]; then
    log "ALLOW_DEFAULT_PASSWORDS=yes -> skipping credential enforcement."
    return
  fi
  require_secret_value "VNC_PASSWORD" "${VNC_PASSWORD:-}" 8 "fs25server"
  require_secret_value "WEB_PASSWORD" "${WEB_PASSWORD:-}" 8 "fs25server"
  local allow_empty_server="${FS25_ALLOW_EMPTY_SERVER_PASSWORD:-no}"
  if [[ "${allow_empty_server,,}" != "yes" ]]; then
    local server_password="${SERVER_PASSWORD:-${FS25_SERVER_PASSWORD:-}}"
    if [[ -n "${server_password}" ]]; then
      require_secret_value "SERVER_PASSWORD" "${server_password}" 8 "fs25server"
    else
      log "SERVER_PASSWORD not supplied via environment; skipping enforcement (set FS25_ALLOW_EMPTY_SERVER_PASSWORD=yes to silence this warning)."
    fi
  fi
}

BASE_HOME="/home/container"
if [[ ! -d "${BASE_HOME}" ]]; then
  BASE_HOME="/home/nobody"
fi
USER="${USER:-container}"

DATA_ROOT="${FS25_DATA_ROOT:-${BASE_HOME}/fs-data}"
SCRIPT_ROOT="${FS25_SCRIPT_ROOT:-${BASE_HOME}/scripts}"
LOG_ROOT="${FS25_LOG_ROOT:-${BASE_HOME}/logs}"
CONFIG_ROOT="${FS25_CONFIG_ROOT:-${BASE_HOME}/runtime}"
INIT_SOURCE="/usr/local/bin/init.sh"
INIT_WRAPPER="${SCRIPT_ROOT}/fs25-init.sh"
BIN_ROOT="${SCRIPT_ROOT}/bin"
ETC_ROOT="${CONFIG_ROOT}/etc"
RUNTIME_HOME="${CONFIG_ROOT}/home"
SUPERVISOR_SOURCE="/etc/supervisor/conf.d"
SUPERVISOR_TARGET="${CONFIG_ROOT}/supervisor/conf.d"
SUPERVISOR_CONF_SOURCE=""
if [[ -f /etc/supervisor.conf ]]; then
  SUPERVISOR_CONF_SOURCE="/etc/supervisor.conf"
elif [[ -f /etc/supervisord.conf ]]; then
  SUPERVISOR_CONF_SOURCE="/etc/supervisord.conf"
fi
SUPERVISOR_CONF_TARGET="${CONFIG_ROOT}/supervisor/supervisor.conf"
BUILD_SOURCE="/home/nobody/.build"
BUILD_TARGET="${BASE_HOME}/.build"
NOBODY_SOURCE="/home/nobody"
NOBODY_TARGET="${BASE_HOME}/nobody-home"
APP_UID=$(id -u)
APP_GID=$(id -g)
LOG_FILE="${LOG_ROOT}/bootstrap.log"
HEALTH_LOG="${LOG_ROOT}/healthcheck.log"
MEDIA_README="${BASE_HOME}/FS25_MEDIA_README.txt"
INSTALLER_GLOB="${DATA_ROOT}/installer/FarmingSimulator2025*.exe"
MEDIA_FLAG="${DATA_ROOT}/.media_pending"
DEDICATED_EXE="${RUNTIME_HOME}/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicatedServer.exe"

mkdir -p "${DATA_ROOT}" "${SCRIPT_ROOT}" "${LOG_ROOT}"
chmod 775 "${DATA_ROOT}" "${SCRIPT_ROOT}" "${LOG_ROOT}"
mkdir -p "${BIN_ROOT}"
rm -f "${BIN_ROOT}/dbus-launch" "${BIN_ROOT}/dbus-update-activation-environment"

mkdir -p "${CONFIG_ROOT}" "${RUNTIME_HOME}"
mkdir -p "${SUPERVISOR_TARGET}"
cp -r "${SUPERVISOR_SOURCE}/." "${SUPERVISOR_TARGET}/"

if [[ -n "${SUPERVISOR_CONF_SOURCE}" ]]; then
  cp "${SUPERVISOR_CONF_SOURCE}" "${SUPERVISOR_CONF_TARGET}"
fi

if [[ -d "${BUILD_SOURCE}" ]]; then
  mkdir -p "${BUILD_TARGET}"
  cp -r "${BUILD_SOURCE}/." "${BUILD_TARGET}/"
fi

if [[ -d "${NOBODY_SOURCE}" ]]; then
  if [[ -z "$(ls -A "${RUNTIME_HOME}" 2>/dev/null)" ]]; then
    cp -a "${NOBODY_SOURCE}/." "${RUNTIME_HOME}/"
  fi
  ln -snf "${RUNTIME_HOME}" "${NOBODY_TARGET}"
fi

touch "${LOG_FILE}" "${HEALTH_LOG}"
chmod 664 "${LOG_FILE}" "${HEALTH_LOG}"

log_stage="init-directories"
log "Container patch ID: ${PATCH_ID}"

safe_chown() {
  local target="$1"
  chown "${APP_UID}:${APP_GID}" "${target}" >/dev/null 2>&1 || true
}

install_path_shims() {
  export PATH="${BIN_ROOT}:${PATH}"
}

prepare_nss_overlay() {
  local uid gid passwd_overlay group_overlay
  uid=$(id -u)
  gid=$(id -g)
  passwd_overlay="${ETC_ROOT}/passwd"
  group_overlay="${ETC_ROOT}/group"

  mkdir -p "${ETC_ROOT}"
  cp /etc/passwd "${passwd_overlay}"
  cp /etc/group "${group_overlay}"

  if ! grep -q ":${uid}:" "${passwd_overlay}"; then
    echo "container:x:${uid}:${gid}:FS25 Container:${RUNTIME_HOME}:/bin/bash" >>"${passwd_overlay}"
  fi

  if ! grep -q ":${gid}:" "${group_overlay}"; then
    echo "container:x:${gid}:container" >>"${group_overlay}"
  fi

  export NSS_WRAPPER_PASSWD="${passwd_overlay}"
  export NSS_WRAPPER_GROUP="${group_overlay}"

  if [[ -z "${LD_PRELOAD:-}" ]]; then
    export LD_PRELOAD="/usr/lib/libnss_wrapper.so"
  else
    export LD_PRELOAD="/usr/lib/libnss_wrapper.so:${LD_PRELOAD}"
  fi
}

prepare_fontconfig() {
  local cache_dir="${FC_CACHEDIR}"
  local source="/etc/fonts/fonts.conf"
  local target="${CONFIG_ROOT}/fontconfig/fonts.conf"

  if [[ ! -f "${source}" ]]; then
    return
  fi

  mkdir -p "$(dirname "${target}")"
  cp "${source}" "${target}"
  local cache_escaped
  cache_escaped=$(printf '%s\n' "${cache_dir}" | sed 's/[\/&]/\\&/g')
  perl -0pi -e "s#<cachedir>.*?</cachedir>#<cachedir>${cache_escaped}</cachedir>#g" "${target}"
  export FONTCONFIG_FILE="${target}"
}

configure_runtime_env() {
  export HOME="${RUNTIME_HOME}"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export XDG_CACHE_HOME="${HOME}/.cache"
  export XDG_DATA_HOME="${HOME}/.local/share"
  export XDG_RUNTIME_DIR="${CONFIG_ROOT}/run"
  export FS25_DBUS_SOCKET="${XDG_RUNTIME_DIR}/dbus-session.sock"
  export FC_CACHEDIR="${XDG_CACHE_HOME}/fontconfig"

  mkdir -p "${XDG_CONFIG_HOME}/pulse" "${XDG_CACHE_HOME}" "${FC_CACHEDIR}" "${XDG_DATA_HOME}" "${XDG_RUNTIME_DIR}"
  chmod 700 "${XDG_RUNTIME_DIR}"
  safe_chown "${XDG_RUNTIME_DIR}"
  prepare_nss_overlay
  prepare_fontconfig
}

prepare_tmp_channels() {
  mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
  chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix
}

ensure_persistent_links() {
  local wine_root="${RUNTIME_HOME}/.fs25server/drive_c"
  if [[ ! -d "${wine_root}" ]]; then
    log "Wine root ${wine_root} missing; skipping persistent link sync"
    return
  fi
  local wine_users_dir="${wine_root}/users"
  local wine_user="${FS25_WINE_USER:-${USER:-nobody}}"
  if [[ -z "${wine_user}" ]]; then
    for candidate in container nobody "${USER:-nobody}"; do
      if [[ -d "${wine_users_dir}/${candidate}" ]]; then
        wine_user="${candidate}"
        break
      fi
    done
  fi
  if [[ -z "${wine_user}" ]]; then
    log "Unable to determine Wine user in ${wine_users_dir}; skipping link sync"
    return
  fi
  if [[ ! -d "${wine_users_dir}/${wine_user}" ]]; then
    log "Wine user directory ${wine_users_dir}/${wine_user} missing; skipping link sync"
    return
  fi

  local wine_docs="${wine_root}/users/${wine_user}/Documents/My Games/FarmingSimulator2025"
  local wine_game="${wine_root}/Program Files (x86)/Farming Simulator 2025"
  local host_docs="${DATA_ROOT}/config/FarmingSimulator2025"
  local host_game="${DATA_ROOT}/game/Farming Simulator 2025"

  link_dir() {
    local host="$1" guest="$2"
    [[ -n "${host}" && -n "${guest}" ]] || return
    mkdir -p "${host}"
    if [[ -L "${guest}" ]]; then
      local target
      target=$(readlink -f "${guest}")
      if [[ "${target}" != "${host}" ]]; then
        rm -f "${guest}"
      else
        return
      fi
    elif [[ -d "${guest}" ]]; then
      if [[ -n "$(ls -A "${guest}" 2>/dev/null)" ]]; then
        cp -a "${guest}/." "${host}/" 2>/dev/null || true
      fi
      rm -rf "${guest}"
    else
      mkdir -p "$(dirname "${guest}")"
    fi
    log "Linking ${guest} -> ${host}"
    if ! ln -s "${host}" "${guest}"; then
      log "Failed to link ${guest} -> ${host}"
      return 1
    fi
  }

  link_dir "${host_docs}" "${wine_docs}" || return
  link_dir "${host_game}" "${wine_game}" || return
}

start_dbus_session() {
  if [[ -z "${FS25_DBUS_SOCKET:-}" ]]; then
    return
  fi

  if [[ -S "${FS25_DBUS_SOCKET}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${FS25_DBUS_SOCKET}"
    return
  fi

  rm -f "${FS25_DBUS_SOCKET}"
  if command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --session --address="unix:path=${FS25_DBUS_SOCKET}" --fork --nopidfile --syslog-only
    safe_chown "${FS25_DBUS_SOCKET}"
    chmod 660 "${FS25_DBUS_SOCKET}" 2>/dev/null || true
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${FS25_DBUS_SOCKET}"
  else
    log "dbus-daemon not available; desktop settings service may not start"
  fi
}

write_media_readme() {
  if [[ -s "${MEDIA_README}" ]]; then
    return
  fi
  cat <<'MEDIA' >"${MEDIA_README}"
===================================================================================================
Farming Simulator 25 media checklist
===================================================================================================
1. Log into https://eshop.giants-software.com/profile/downloads using the account that owns your FS25 
   dedicated server license.
2. Download the official installer (FarmingSimulator2025.exe) and any DLC/expansion executables.
3. Upload the base installer into /home/container/fs-data/installer/ via the Pterodactyl file manager or SFTP.
4. Upload each DLC executable into /home/container/fs-data/dlc/.
5. Restart the server. The container will automatically pick them up and run the setup script.

You can import this egg and boot the server before the downloads finish. The desktop will simply show a
"media pending" notice until the files arrive.
===================================================================================================
MEDIA
}

ensure_opt_mount() {
  local target="/opt/fs25"

  if ! touch /opt/.fs25_rw 2>/dev/null; then
    log "/opt is read-only; using ${DATA_ROOT} directly"
    return
  fi
  rm -f /opt/.fs25_rw

  if [[ -L "${target}" ]]; then
    local current
    current=$(readlink -f "${target}")
    if [[ "${current}" == "${DATA_ROOT}" ]]; then
      return
    fi
    rm -f "${target}"
  elif [[ -e "${target}" ]]; then
    if [[ -d "${target}" ]]; then
      log "Migrating existing ${target} into ${DATA_ROOT}"
      mkdir -p "${DATA_ROOT}"
      cp -a "${target}/." "${DATA_ROOT}/"
    fi
    rm -rf "${target}"
  fi
  ln -s "${DATA_ROOT}" "${target}"
}

create_data_tree() {
  for dir in config game installer dlc backups media; do
    mkdir -p "${DATA_ROOT}/${dir}"
  done
}

have_installer() {
  compgen -G "${INSTALLER_GLOB}" >/dev/null 2>&1
}

have_installed_payload() {
  [[ -f "${DEDICATED_EXE}" ]]
}

summarise_media_state() {
  if have_installer || have_installed_payload; then
    rm -f "${MEDIA_FLAG}"
    if have_installed_payload && ! have_installer; then
      log "Existing installation found (dedicatedServer.exe present); skipping installer requirement."
    else
      log "Installer detected. Ready for setup."
    fi
  else
    printf "WARNING: FarmingSimulator2025.exe not found. Upload it to %s/installer/.\n" "${DATA_ROOT}" >"${MEDIA_FLAG}"
    log "Installer missing - server will stay in media-pending mode until it is uploaded."
  fi
}

patch_supervisor_conf() {
  if [[ ! -f "${SUPERVISOR_CONF_TARGET}" ]]; then
    return
  fi

  local socket="${CONFIG_ROOT}/supervisor/supervisor.sock"
  local include_glob="${SUPERVISOR_TARGET}/*.conf"
  local pidfile="${CONFIG_ROOT}/supervisor/supervisord.pid"
  mkdir -p "$(dirname "${socket}")"
  mkdir -p "$(dirname "${pidfile}")"

  FS25_SUP_SOCKET="${socket}" perl -0pi -e 'my $sock = $ENV{FS25_SUP_SOCKET}; s/(\[unix_http_server\][^\[]*?file\s*=\s*).+?(\r?\n)/${1}$sock$2/s' "${SUPERVISOR_CONF_TARGET}"
  FS25_SUP_SOCKET="${socket}" perl -0pi -e 'my $sock = $ENV{FS25_SUP_SOCKET}; s/(\[supervisorctl\][^\[]*?serverurl\s*=\s*).+?(\r?\n)/${1}unix:\/\/$sock$2/s' "${SUPERVISOR_CONF_TARGET}"
  FS25_SUP_INCLUDE="${include_glob}" perl -0pi -e 'my $glob = $ENV{FS25_SUP_INCLUDE}; s/(\[include\][^\[]*?files\s*=\s*).+?(\r?\n)/${1}$glob$2/s' "${SUPERVISOR_CONF_TARGET}"
  FS25_SUP_PIDFILE="${pidfile}" python3 - "$SUPERVISOR_CONF_TARGET" <<'PY'
import os
import re
import sys

pid = os.environ["FS25_SUP_PIDFILE"]
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = fh.read()

pattern = re.compile(r'(\[supervisord\][\s\S]*?)(?=\n\[|\Z)', re.MULTILINE)

def repl(match):
    block = match.group(1)
    block = re.sub(r'^\s*pidfile\s*=.*$', '', block, flags=re.MULTILINE)
    block = block.rstrip() + f"\npidfile = {pid}\n"
    return block

new, count = pattern.subn(repl, data, count=1)

if count == 0:
    new = data.rstrip() + f"\n[supervisord]\npidfile = {pid}\n"

with open(path, "w", encoding="utf-8") as fh:
    fh.write(new)
PY

  sed -i '/^\s*user\s*=.*/d' "${SUPERVISOR_CONF_TARGET}"

  mapfile -t _supervisor_confs < <(find "${SUPERVISOR_TARGET}" -type f -name '*.conf' 2>/dev/null)
  if ((${#_supervisor_confs[@]})); then
    sed -i '/^\s*user\s*=.*/d' "${_supervisor_confs[@]}"
  fi

  log "Rewired supervisor socket/include paths into ${CONFIG_ROOT}"
}

patch_init_config() {
  local target="$1"
  local marker="${target}.patched"
  local escaped
  escaped=$(printf '%s\n' "${CONFIG_ROOT}" | sed 's/[\/&]/\\&/g')
  sed -i "s#/config/#${escaped}/#g" "${target}"
  sed -i "s#/config#${escaped}#g" "${target}"

  local supervisor_escaped
  supervisor_escaped=$(printf '%s\n' "${SUPERVISOR_TARGET}" | sed 's/[\/&]/\\&/g')
  sed -i "s#/etc/supervisor/conf.d#${supervisor_escaped}#g" "${target}"

  if [[ -d "${BUILD_SOURCE}" ]]; then
    local build_escaped
    build_escaped=$(printf '%s\n' "${BUILD_TARGET}" | sed 's/[\/&]/\\&/g')
    sed -i "s#/home/nobody/.build#${build_escaped}#g" "${target}"
  fi

  if [[ -d "${NOBODY_SOURCE}" ]]; then
    local home_escaped
    home_escaped=$(printf '%s\n' "${NOBODY_TARGET}" | sed 's/[\/&]/\\&/g')
    sed -i "s#/home/nobody#${home_escaped}#g" "${target}"
  fi


  if [[ -n "${SUPERVISOR_CONF_SOURCE}" ]]; then
    local conf_escaped
    conf_escaped=$(printf '%s\n' "${SUPERVISOR_CONF_TARGET}" | sed 's/[\/&]/\\&/g')
    sed -i "s#/etc/supervisor.conf#${conf_escaped}#g" "${target}"
    sed -i "s#/etc/supervisord.conf#${conf_escaped}#g" "${target}"
    patch_supervisor_conf
  fi

  perl -0pi -e 's/# NOTE Do not move PUID.*?# ENVVARS_COMMON_PLACEHOLDER/echo "[info] Skipping Binhex init preamble (handled by bootstrap)" | ts %\Y-%m-%d %H:%M:%S\n\n# ENVVARS_COMMON_PLACEHOLDER/gs' "${target}"
  perl -0pi -e 's/# get previous puid\/pgid.*?echo "\$\{PGID\}" > \/root\/pgid/echo "[info] PUID\/PGID managed by Wings" | ts %\Y-%m-%d %H:%M:%S/gs' "${target}"
  touch "${marker}"
  log "Patched init wrapper for runtime dirs (config=${CONFIG_ROOT}, supervisor=${SUPERVISOR_TARGET})"
}

prepare_init_wrapper() {
  if [[ ! -f "${INIT_SOURCE}" ]]; then
    log "init.sh not found at ${INIT_SOURCE}"
    exit 1
  fi
  cp "${INIT_SOURCE}" "${INIT_WRAPPER}"
  chmod +x "${INIT_WRAPPER}"
  patch_init_config "${INIT_WRAPPER}"
}

mask_upstream_secrets() {
  local target="${INIT_WRAPPER}"
  [[ -f "${target}" ]] || return
  python3 - "${target}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_text()
patterns = [
    (r"VNC_PASSWORD defined as '.*?'", "VNC_PASSWORD defined as '<hidden>'"),
    (r"WEB_PASSWORD defined as '.*?'", "WEB_PASSWORD defined as '<hidden>'"),
    (r"SERVER_PASSWORD defined as '.*?'", "SERVER_PASSWORD defined as '<hidden>'"),
]

new = data
for pattern, replacement in patterns:
    new = re.sub(pattern, replacement, new)

if new != data:
    path.write_text(new)
PY
  log "Patched init wrapper to mask sensitive password logs"
}

start_health_monitor() {
  local hc="/usr/local/bin/fs25-healthcheck.sh"
  if [[ ! -x "${hc}" ]]; then
    log "Healthcheck script missing"
    return
  fi
  if pgrep -f gm-healthcheck >/dev/null 2>&1; then
    log "Healthcheck already running"
    return
  fi
  log "Starting health monitor"
  FS25_HEALTH_LOG="${HEALTH_LOG}" nohup "${hc}" >"${HEALTH_LOG}" 2>&1 &
}

start_log_forwarder() {
  local forwarder="/usr/local/bin/fs25-log-forwarder.sh"
  if [[ ! -x "${forwarder}" ]]; then
    log "Log forwarder script missing"
    return
  fi
  (
    export FS25_LOG_DIR="${DATA_ROOT}/config/FarmingSimulator2025"
    "${forwarder}"
  ) &
  log "Log forwarder started (PID $!)"
}

apply_web_portal_config() {
  local cfg="${DATA_ROOT}/game/Farming Simulator 2025/dedicatedServer.xml"
  if [[ ! -f "${cfg}" ]]; then
    return
  fi

  local args=()
  [[ -n "${WEB_PORT:-}" ]] && args+=("WEB_PORT=${WEB_PORT}")
  [[ -n "${WEB_USERNAME:-}" ]] && args+=("WEB_USERNAME=${WEB_USERNAME}")
  [[ -n "${WEB_PASSWORD:-}" ]] && args+=("WEB_PASSWORD=${WEB_PASSWORD}")
  [[ -n "${WEB_SCHEME:-}" ]] && args+=("WEB_SCHEME=${WEB_SCHEME}")

  if ((${#args[@]})); then
    if /usr/local/bin/fs25-configure-web.sh "${cfg}" "${args[@]}"; then
      log "Applied web portal defaults to dedicatedServer.xml"
    else
      log "Failed to update dedicatedServer.xml"
    fi
  fi
}

sync_portal_logos() {
  local cfg="${DATA_ROOT}/game/Farming Simulator 2025/dedicatedServer.xml"
  [[ -f "${cfg}" ]] || return

  local upload_dir="${DATA_ROOT}/media"
  local template_targets=()
  local runtime_template="${RUNTIME_HOME}/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicated_server/webroot/template"
  local legacy_template="/home/nobody/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicated_server/webroot/template"
  local persistent_template="${DATA_ROOT}/game/Farming Simulator 2025/dedicated_server/webroot/template"
  local config_template="${DATA_ROOT}/config/FarmingSimulator2025/dedicated_server/webroot/template"
  local web_data_template="${DATA_ROOT}/game/Farming Simulator 2025/web_data/template"

  if [[ -n "${runtime_template}" ]]; then
    template_targets+=("${runtime_template}")
  fi
  if [[ -d "/home/nobody/.fs25server" && "${legacy_template}" != "${runtime_template}" ]]; then
    template_targets+=("${legacy_template}")
  fi
  if [[ -n "${persistent_template}" ]]; then
    template_targets+=("${persistent_template}")
  fi
  if [[ -n "${config_template}" ]]; then
    template_targets+=("${config_template}")
  fi
  if [[ -n "${web_data_template}" ]]; then
    template_targets+=("${web_data_template}")
  fi

  if ((${#template_targets[@]} == 0)); then
    log "No dedicated_server template directories detected; skipping portal logo sync"
    return
  fi
  local args=()
  local login_rel=""
  local bottom_rel=""
  local LOGO_RESULT=""

  copy_logo() {
    local src_name="$1"
    local dest_stub="$2"
    [[ -n "${src_name}" ]] || return
    local src_path="${upload_dir}/${src_name}"
    if [[ ! -f "${src_path}" ]]; then
      log "Portal logo ${src_name} not found under ${upload_dir}"
      return
    fi
    local ext="${src_name##*.}"
    if [[ "${ext}" == "${src_name}" ]]; then
      ext="jpg"
    fi
    local lower_ext
    lower_ext=$(echo "${ext}" | tr '[:upper:]' '[:lower:]')
    local dest_file="${dest_stub}.${lower_ext}"
    local copied=0
    for target in "${template_targets[@]}"; do
      mkdir -p "${target}"
      local dest="${target}/${dest_file}"
      if [[ -e "${dest}" ]]; then
        local src_real dest_real
        src_real=$(readlink -f "${src_path}" 2>/dev/null || echo "${src_path}")
        dest_real=$(readlink -f "${dest}" 2>/dev/null || echo "${dest}")
        if [[ "${src_real}" == "${dest_real}" ]]; then
          copied=1
          continue
        fi
        if cmp -s "${src_real}" "${dest_real}" 2>/dev/null; then
          copied=1
          continue
        fi
      fi
      if cp -f "${src_path}" "${dest}"; then
        copied=1
      else
        log "Failed to copy ${src_name} into ${dest}"
      fi
    done
    if ((copied)); then
      log "Updated ${dest_stub} logo (${src_name} -> template/${dest_file})"
      LOGO_RESULT="template/${dest_file}"
    else
      LOGO_RESULT=""
    fi
  }

  if [[ -n "${WEB_PORTAL_LOGIN_LOGO:-}" ]]; then
    LOGO_RESULT=""
    copy_logo "${WEB_PORTAL_LOGIN_LOGO}" "loginLogo"
    login_rel="${LOGO_RESULT}"
  fi

  if [[ -n "${WEB_PORTAL_FOOTER_LOGO:-}" ]]; then
    LOGO_RESULT=""
    copy_logo "${WEB_PORTAL_FOOTER_LOGO}" "bottomLogo"
    bottom_rel="${LOGO_RESULT}"
  elif [[ -n "${login_rel}" ]]; then
    bottom_rel="${login_rel}"
  fi

  [[ -n "${login_rel}" ]] && args+=("LOGIN_LOGO=${login_rel}")
  [[ -n "${bottom_rel}" ]] && args+=("BOTTOM_LOGO=${bottom_rel}")

  if ((${#args[@]})); then
    if /usr/local/bin/fs25-configure-web.sh "${cfg}" "${args[@]}"; then
      log "Configured portal logos in dedicatedServer.xml"
    else
      log "Failed to update portal logos in dedicatedServer.xml"
    fi
  fi
}

auto_start_fs25() {
  local flag="${AUTO_START_FS25:-no}"
  local media_pending=0
  if [[ -f "${MEDIA_FLAG}" ]]; then
    media_pending=1
  fi
  case "${flag,,}" in
    yes|true|1|on)
      if (( media_pending )); then
        log "Media still pending; skipping auto-start until FarmingSimulator2025.exe is uploaded"
        return
      fi
      if [[ ! -f "${DEDICATED_EXE}" ]]; then
        log "dedicatedServer.exe not present yet; skipping auto-start this boot"
        return
      fi
      if ! command -v start_fs25.sh >/dev/null 2>&1; then
        log "start_fs25.sh not found; cannot auto-start dedicated server"
        return
      fi
      log "Auto-starting Giants dedicated server UI (AUTO_START_FS25=${flag})"
      nohup start_fs25.sh >>"${LOG_ROOT}/fs25-autostart.log" 2>&1 &
      ;;
  esac
}

main() {
  log_stage="enforce-credentials"
  enforce_required_credentials
  log_stage="write-media-readme"
  write_media_readme
  log_stage="create-data-tree"
  create_data_tree
  log_stage="ensure-opt-mount"
  ensure_opt_mount
  log_stage="configure-runtime-env"
  configure_runtime_env
  log_stage="start-dbus-session"
  start_dbus_session
  log_stage="prepare-tmp-channels"
  prepare_tmp_channels
  log_stage="ensure-links"
  ensure_persistent_links || true
  log_stage="install-shims"
  install_path_shims
  log_stage="prepare-init-wrapper"
  prepare_init_wrapper
  log_stage="mask-upstream-secrets"
  mask_upstream_secrets
  log_stage="summarise-media"
  summarise_media_state
  log_stage="apply-web-config"
  apply_web_portal_config
  log_stage="sync-logos"
  sync_portal_logos
  log_stage="start-health-monitor"
  start_health_monitor
  log_stage="start-log-forwarder"
  start_log_forwarder
  log_stage="auto-start-fs25"
  auto_start_fs25
  log_stage="handoff-init"
  log "Handing off to ${INIT_WRAPPER}"
  export FS25_INSTALL_ROOT="${DATA_ROOT}"
  exec /bin/bash "${INIT_WRAPPER}" "$@"
}

main "$@"
