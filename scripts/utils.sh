#!/bin/bash

# Minimal helper shim for Binhex init scripts when running without the full
# utils package. Currently only ts() is required.

ts() {
  if command -v ts >/dev/null 2>&1; then
    command ts "$@"
  else
    # Fallback: mimic ts output by prefixing timestamps manually
    while IFS= read -r line; do
      printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
    done
  fi
}
