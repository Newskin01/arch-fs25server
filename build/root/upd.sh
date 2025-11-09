#!/bin/bash
set -euo pipefail

: "${TARGETARCH:=amd64}"
: "${SKIP_FULL_UPGRADE:=yes}"
: "${pacman_confirm:=no}"

mirrorlist="/etc/pacman.d/mirrorlist"

create_static_mirrorlist() {
    if [[ "${TARGETARCH}" == "amd64" ]]; then
        cat <<'EOF' > "${mirrorlist}"
Server = https://arch.mirror.constant.com/$repo/os/$arch
Server = https://arch.mirror.square-r00t.net/$repo/os/$arch
Server = http://arch.mirror.square-r00t.net/$repo/os/$arch
Server = rsync://arch.mirror.constant.com/archlinux/$repo/os/$arch
Server = rsync://arch.mirror.square-r00t.net/arch/$repo/os/$arch
EOF
    else
        cat <<'EOF' > "${mirrorlist}"
Server = http://eu.mirror.archlinuxarm.org/$arch/$repo
EOF
    fi
}

echo "[info] Using static pacman mirrorlist for TARGETARCH='${TARGETARCH}'"
create_static_mirrorlist

if [[ -n "${pacman_ignore_packages:-}" ]]; then
    echo "[info] Ignoring package(s) '${pacman_ignore_packages}' from upgrade/install"
    sed -i -e "s~^#IgnorePkg.*~IgnorePkg = ${pacman_ignore_packages}~g" "/etc/pacman.conf"
fi

if [[ -n "${pacman_ignore_group_packages:-}" ]]; then
    echo "[info] Ignoring package group(s) '${pacman_ignore_group_packages}' from upgrade/install"
    sed -i -e "s~^#IgnoreGroup.*~IgnoreGroup = ${pacman_ignore_group_packages}~g" "/etc/pacman.conf"
fi

echo "[info] Showing pacman configuration file '/etc/pacman.conf'..."
cat "/etc/pacman.conf"

if [[ "${SKIP_FULL_UPGRADE}" == "yes" ]]; then
    echo "[info] SKIP_FULL_UPGRADE=yes, running lightweight pacman sync (no upgrade)"
    pacman -Syy --noconfirm
else
    echo "[info] Running full pacman -Syyu upgrade (SKIP_FULL_UPGRADE=no)"
    if [[ "${pacman_confirm}" == "yes" ]]; then
        yes | pacman -Syyu
    else
        pacman -Syyu --noconfirm
    fi
fi
