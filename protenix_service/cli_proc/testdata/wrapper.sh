#!/bin/bash
# 模拟包装子壳：拉起上游子进程后 wait。只向本壳发 SIGTERM 时子进程会留下。
set -eu
if [[ "${1:-}" == "ok" ]]; then
  echo wrapper-ok
  exit 0
fi
bash "$CHILD_SCRIPT" &
child_pid=$!
echo "$child_pid" > "$CHILD_PID_FILE.wait"
wait "$child_pid"
