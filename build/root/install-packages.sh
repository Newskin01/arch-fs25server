#!/bin/bash
set -euo pipefail

: "${FAST_INSTALL:=yes}"
: "${SKIP_FULL_UPGRADE:=yes}"
: "${pacman_packages:=wine-staging samba exo garcon thunar xfce4-appfinder tumbler xfce4-panel xfce4-session xfce4-settings xfce4-terminal xfconf xfdesktop xfwm4 xfwm4-themes}"

pacman -Sy --noconfirm

if [[ "${FAST_INSTALL}" != "yes" ]]; then
    source /tmp/upd.sh
elif [[ "${SKIP_FULL_UPGRADE}" != "yes" ]]; then
    source /tmp/upd.sh
fi

if [[ -n "${pacman_packages}" ]]; then
    pacman -S --needed ${pacman_packages} --noconfirm
fi

pacman -Scc --noconfirm
