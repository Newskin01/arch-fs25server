#!/bin/bash
set -euo pipefail

LOG_DIR="${FS25_LOG_DIR:-/home/container/fs-data/config/FarmingSimulator2025}"
DEDICATED_DIR="${LOG_DIR}/dedicated_server/logs"
STATIC_TARGETS=(
  "${LOG_DIR}/log.txt"
  "${DEDICATED_DIR}/server.log"
  "${DEDICATED_DIR}/webserver.log"
)

mkdir -p "${LOG_DIR}" "${DEDICATED_DIR}"
trap 'pkill -P $$ >/dev/null 2>&1 || true' EXIT

start_tail() {
  local file="$1"
  local label="$2"
  touch "$file"
  stdbuf -oL tail -n0 -F "$file" |
    while IFS= read -r line; do
      printf '[%s] %s\n' "${label}" "${line}"
    done &
}

for target in "${STATIC_TARGETS[@]}"; do
  start_tail "$target" "$(basename "$target")"
done

current_dynamic=""
dynamic_pid=""

while true; do
  new_file=$(ls -1t "${LOG_DIR}"/log_*.txt 2>/dev/null | head -1 || true)
  if [[ -n "${new_file}" && "${new_file}" != "${current_dynamic}" ]]; then
    [[ -n "${dynamic_pid}" ]] && kill "${dynamic_pid}" >/dev/null 2>&1 || true
    label="$(basename "${new_file}")"
    stdbuf -oL tail -n0 -F "${new_file}" |
      while IFS= read -r line; do
        printf '[%s] %s\n' "${label}" "${line}"
      done &
    dynamic_pid=$!
    current_dynamic="${new_file}"
    echo "[fs25-log-forwarder] following ${new_file}" >&2
  fi
  sleep 5
done
