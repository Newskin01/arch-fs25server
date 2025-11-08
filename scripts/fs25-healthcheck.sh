#!/bin/bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8443}"
WEB_SCHEME="${WEB_SCHEME:-http}"
GAME_PORT="${SERVER_PORT:-10823}"
LOG_FILE="${FS25_HEALTH_LOG:-/home/container/logs/healthcheck.log}"
FLAG="/tmp/fs25_health_ready"
STATE="unknown"

log() {
  local ts
  ts=$(date --iso-8601=seconds)
  local line="[fs25-healthcheck] ${ts} $*"
  if [[ -n "${LOG_FILE}" ]]; then
    echo "${line}" >>"${LOG_FILE}"
  fi
  echo "${line}"
}

check_web() {
  curl -ks --max-time 5 "${WEB_SCHEME}://127.0.0.1:${WEB_PORT}/" >/dev/null
}

check_game() {
  ss -lntu | grep -q ":${GAME_PORT} "
}

while true; do
  if check_web && check_game; then
    if [[ "${STATE}" != "ready" ]]; then
      log "state=ready"
    fi
    STATE="ready"
    if [[ ! -f "${FLAG}" ]]; then
      echo "FS25_HEALTHCHECK=PASS $(date --iso-8601=seconds)"
      touch "${FLAG}"
    fi
  else
    if [[ "${STATE}" != "pending" ]]; then
      log "state=pending"
    fi
    STATE="pending"
    rm -f "${FLAG}"
  fi
  sleep 30
done
