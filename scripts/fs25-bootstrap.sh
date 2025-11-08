#!/bin/bash
set -euo pipefail

LOG_FILE=""

log() {
  local ts
  ts=$(date --iso-8601=seconds)
  local line="[fs25-bootstrap] ${ts} $*"
  if [[ -n "${LOG_FILE}" ]]; then
    echo "${line}" >>"${LOG_FILE}"
  fi
  echo "${line}"
}

BASE_HOME="/home/container"
if [[ ! -d "${BASE_HOME}" ]]; then
  BASE_HOME="/home/nobody"
fi

DATA_ROOT="${FS25_DATA_ROOT:-${BASE_HOME}/fs-data}"
SCRIPT_ROOT="${FS25_SCRIPT_ROOT:-${BASE_HOME}/scripts}"
LOG_ROOT="${FS25_LOG_ROOT:-${BASE_HOME}/logs}"
LOG_FILE="${LOG_ROOT}/bootstrap.log"
HEALTH_LOG="${LOG_ROOT}/healthcheck.log"
MEDIA_README="${BASE_HOME}/FS25_MEDIA_README.txt"
INSTALLER_GLOB="${DATA_ROOT}/installer/FarmingSimulator2025*.exe"
MEDIA_FLAG="${DATA_ROOT}/.media_pending"

mkdir -p "${DATA_ROOT}" "${SCRIPT_ROOT}" "${LOG_ROOT}"
chmod 775 "${DATA_ROOT}" "${SCRIPT_ROOT}" "${LOG_ROOT}"

touch "${LOG_FILE}" "${HEALTH_LOG}"
chmod 664 "${LOG_FILE}" "${HEALTH_LOG}"

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
  for dir in config game installer dlc backups; do
    mkdir -p "${DATA_ROOT}/${dir}"
  done
}

summarise_media_state() {
  if ls ${INSTALLER_GLOB} >/dev/null 2>&1; then
    rm -f "${MEDIA_FLAG}"
    log "Installer detected. Ready for setup."
  else
    printf "WARNING: FarmingSimulator2025.exe not found. Upload it to %s/installer/.\n" "${DATA_ROOT}" >"${MEDIA_FLAG}"
    log "Installer missing - server will stay in media-pending mode until it is uploaded."
  fi
}

patch_env_vars() {
  declare -A mapping=(
    [FS25_SERVER_NAME]=SERVER_NAME
    [FS25_SERVER_PASSWORD]=SERVER_PASSWORD
    [FS25_SERVER_ADMIN]=SERVER_ADMIN
    [FS25_SERVER_PLAYERS]=SERVER_PLAYERS
    [FS25_SERVER_DIFFICULTY]=SERVER_DIFFICULTY
    [FS25_SERVER_SAVE_INTERVAL]=SERVER_SAVE_INTERVAL
    [FS25_SERVER_STATS_INTERVAL]=SERVER_STATS_INTERVAL
    [FS25_SERVER_CROSSPLAY]=SERVER_CROSSPLAY
    [FS25_SERVER_MAP]=SERVER_MAP
    [FS25_SERVER_PAUSE]=SERVER_PAUSE
    [FS25_SERVER_REGION]=SERVER_REGION
  )

  for src in "${!mapping[@]}"; do
    local dest="${mapping[$src]}"
    local value="${!src:-}"
    if [[ -n "${value}" ]]; then
      export "${dest}=${value}"
    fi
  done
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

main() {
  write_media_readme
  create_data_tree
  ensure_opt_mount
  summarise_media_state
  patch_env_vars
  start_health_monitor
  log "Handing off to init.sh"
  exec /bin/bash /usr/local/bin/init.sh "$@"
}

main "$@"
