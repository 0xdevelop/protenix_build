#!/bin/bash
set -euo pipefail

project_path=$(cd "$(dirname "$0")" && pwd)
cd "${project_path}"

if ! command -v go >/dev/null 2>&1; then
  echo "[gen_pre_build_config] go not found in PATH" >&2
  exit 1
fi

usage() {
  echo "Usage: $0 <linux_amd64|linux_arm64|validate <yaml>|export <yaml>|all>" >&2
  exit 2
}

case "${1:-}" in
  linux_amd64|linux_arm64)
    go run gen_pre_build_config.go -target "$1"
    ;;
  all)
    go run gen_pre_build_config.go -target linux_amd64
    go run gen_pre_build_config.go -target linux_arm64
    ;;
  validate)
    [[ -n "${2:-}" ]] || usage
    go run gen_pre_build_config.go -validate "$2"
    ;;
  export)
    [[ -n "${2:-}" ]] || usage
    go run gen_pre_build_config.go -export "$2"
    ;;
  *)
    usage
    ;;
esac
