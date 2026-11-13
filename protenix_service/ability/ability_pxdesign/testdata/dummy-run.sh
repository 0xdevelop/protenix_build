#!/bin/bash
set -eu
argv_file="${DUMMY_ARGV_FILE:-./argv.txt}"
printf '%q ' "$0" "$@" > "$argv_file"
echo >> "$argv_file"
if [[ "${DUMMY_SLEEP:-0}" == "1" ]]; then
  sleep 30
fi
if [[ "${DUMMY_WRITE_CIF:-0}" == "1" ]]; then
  out=""
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--out_dir" || "$prev" == "--dump_dir" ]]; then
      out="$arg"
    fi
    prev="$arg"
  done
  if [[ -n "$out" ]]; then
    mkdir -p "$out"
    echo data_dummy > "$out/dummy.cif"
  fi
fi
exit 0
