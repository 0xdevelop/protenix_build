#!/bin/bash
set -eu
echo $$ > "$CHILD_PID_FILE"
while true; do
  date +%s.%N >> "$HEARTBEAT_FILE"
  sleep 0.1
done
