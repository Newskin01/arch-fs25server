#!/bin/bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8443}"
WEB_SCHEME="${WEB_SCHEME:-http}"
GAME_PORT="${SERVER_PORT:-10823}"
LOG_FILE="${FS25_HEALTH_LOG:-/home/container/logs/healthcheck.log}"
FLAG="/tmp/fs25_health_ready"
STATE="unknown"
LAST_WEB_STATUS="unknown"
LAST_GAME_STATUS="unknown"

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
  local code
  code=$(curl -ks --max-time 5 -o /dev/null -w "%{http_code}" "${WEB_SCHEME}://127.0.0.1:${WEB_PORT}/" 2>/dev/null || echo "000")
  WEB_STATUS="${code}"
  [[ "${code}" != "000" ]]
}

check_game() {
  if ss -lntu | grep -q ":${GAME_PORT} "; then
    GAME_STATUS="listening"
    return 0
  fi
  GAME_STATUS="closed"
  return 1
}

while true; do
  WEB_STATUS="unknown"
  GAME_STATUS="unknown"
  if check_web && check_game; then
    if [[ "${STATE}" != "ready" || "${WEB_STATUS}" != "${LAST_WEB_STATUS}" || "${GAME_STATUS}" != "${LAST_GAME_STATUS}" ]]; then
      log "state=ready web=${WEB_STATUS} game=${GAME_STATUS}"
    fi
    STATE="ready"
    if [[ ! -f "${FLAG}" ]]; then
      echo "FS25_HEALTHCHECK=PASS $(date --iso-8601=seconds)"
      touch "${FLAG}"
    fi
  else
    if [[ "${STATE}" != "pending" || "${WEB_STATUS}" != "${LAST_WEB_STATUS}" || "${GAME_STATUS}" != "${LAST_GAME_STATUS}" ]]; then
      log "state=pending web=${WEB_STATUS} game=${GAME_STATUS}"
    fi
    STATE="pending"
    rm -f "${FLAG}"
  fi
  LAST_WEB_STATUS="${WEB_STATUS}"
  LAST_GAME_STATUS="${GAME_STATUS}"
  sleep 30
done
