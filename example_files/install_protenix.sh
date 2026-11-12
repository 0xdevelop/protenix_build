#!/bin/bash
# 安装 Go supervisor + wrapper/env/unit 到 prefix。不装 GPU/pip。
set -euo pipefail

APP_NAME=protenix
PREFIX="${PROTENIX_INSTALL_PREFIX:-/opt/protenix_build/prefix/protenix}"
SYSTEMD_PATH="${SYSTEMD_PATH:-/etc/systemd/system}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

echo "[install_${APP_NAME}] target prefix=${PREFIX}"
mkdir -p "${PREFIX}/bin" "${PREFIX}/conf" "${PREFIX}/systemd" "${PREFIX}/scripts" "${PREFIX}/logs"

[[ -f "${SCRIPT_DIR}/bin/protenixd" ]] || { echo "[install_${APP_NAME}] missing bin/protenixd" >&2; exit 1; }
cp -f "${SCRIPT_DIR}/bin/protenixd" "${PREFIX}/bin/protenixd"
chmod a+x "${PREFIX}/bin/protenixd"
cp -f "${SCRIPT_DIR}/bin/protenix-run" "${PREFIX}/bin/protenix-run"
chmod a+x "${PREFIX}/bin/protenix-run"

if [[ -f "${PREFIX}/conf/protenix.env" ]]; then
  cp -f "${SCRIPT_DIR}/conf/protenix.env" "${PREFIX}/conf/protenix.env.new"
else
  cp -f "${SCRIPT_DIR}/conf/protenix.env" "${PREFIX}/conf/protenix.env"
fi
cp -f "${SCRIPT_DIR}/systemd/"*.service "${PREFIX}/systemd/" 2>/dev/null || true
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
  cp -f "${SCRIPT_DIR}/scripts/"*.sh "${PREFIX}/scripts/" 2>/dev/null || true
  chmod a+x "${PREFIX}/scripts/"*.sh 2>/dev/null || true
fi
[[ -f "${SCRIPT_DIR}/BUILD_INFO.txt" ]] && cp -f "${SCRIPT_DIR}/BUILD_INFO.txt" "${PREFIX}/BUILD_INFO.txt"

if [[ "${INSTALL_SYSTEMD:-0}" == "1" ]]; then
  mkdir -p "${SYSTEMD_PATH}"
  cp -f "${PREFIX}/systemd/protenix.service" "${SYSTEMD_PATH}/protenix.service"
  [[ -f "${PREFIX}/systemd/protenix-oneshot.service" ]] && cp -f "${PREFIX}/systemd/protenix-oneshot.service" "${SYSTEMD_PATH}/protenix-oneshot.service"
  if [[ "${SYSTEMD_PATH}" == *"/systemd/user"* ]]; then
    systemctl --user daemon-reload
    systemctl --user enable protenix.service || true
    echo "[install_${APP_NAME}] enabled --user protenix.service; oneshot 模板已拷贝"
  else
    systemctl daemon-reload
    systemctl enable protenix.service || true
    echo "[install_${APP_NAME}] enabled protenix.service; oneshot 模板已拷贝"
  fi
else
  echo "[install_${APP_NAME}] skip systemd (set INSTALL_SYSTEMD=1)"
fi

echo "[install_${APP_NAME}] done. primary=${PREFIX}/bin/protenixd cli=${PREFIX}/bin/protenix-run"
