#!/bin/bash

export WINEDEBUG=-all
export WINEPREFIX=~/.fs25server

# Start the server

GAME_EXE="$HOME/.fs25server/drive_c/Program Files (x86)/Farming Simulator 2025/dedicatedServer.exe"
WEB_HOST="${CONTAINER_IP:-127.0.0.1}"
WEB_PORT="${WEB_PORT:-7999}"
WEB_SCHEME="${WEB_SCHEME:-http}"
WEB_USER="${WEB_USERNAME:-admin}"
WEB_PASS="${WEB_PASSWORD:-admin}"
WEB_LANG="${WEB_LANGUAGE:-en}"

if [ -f "$GAME_EXE" ]; then
    wine "$GAME_EXE" &
    sleep 1
    if command -v firefox >/dev/null 2>&1; then
        firefox "${WEB_SCHEME}://${WEB_HOST}:${WEB_PORT}/index.html?lang=${WEB_LANG}&username=${WEB_USER}&password=${WEB_PASS}&login=Login" >/dev/null 2>&1 &
    fi
else
    echo "Game not installed?" >&2
    exit 1
fi

exit 0
