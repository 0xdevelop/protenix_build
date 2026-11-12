#!/bin/bash
# 安装 Go supervisor + wrapper/env/unit 到 prefix。不装 GPU/pip。
set -euo pipefail

APP_NAME=pxdesign
PREFIX="${PXDESIGN_INSTALL_PREFIX:-/opt/protenix_build/prefix/pxdesign}"
SYSTEMD_PATH="${SYSTEMD_PATH:-/etc/systemd/system}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

echo "[install_${APP_NAME}] target prefix=${PREFIX}"
mkdir -p "${PREFIX}/bin" "${PREFIX}/conf" "${PREFIX}/systemd" "${PREFIX}/scripts" "${PREFIX}/logs"

[[ -f "${SCRIPT_DIR}/bin/pxdesignd" ]] || { echo "[install_${APP_NAME}] missing bin/pxdesignd" >&2; exit 1; }
cp -f "${SCRIPT_DIR}/bin/pxdesignd" "${PREFIX}/bin/pxdesignd"
chmod a+x "${PREFIX}/bin/pxdesignd"
cp -f "${SCRIPT_DIR}/bin/pxdesign-run" "${PREFIX}/bin/pxdesign-run"
chmod a+x "${PREFIX}/bin/pxdesign-run"

if [[ -f "${PREFIX}/conf/pxdesign.env" ]]; then
  cp -f "${SCRIPT_DIR}/conf/pxdesign.env" "${PREFIX}/conf/pxdesign.env.new"
else
  cp -f "${SCRIPT_DIR}/conf/pxdesign.env" "${PREFIX}/conf/pxdesign.env"
fi
cp -f "${SCRIPT_DIR}/systemd/"*.service "${PREFIX}/systemd/" 2>/dev/null || true
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
  cp -f "${SCRIPT_DIR}/scripts/"*.sh "${PREFIX}/scripts/" 2>/dev/null || true
  chmod a+x "${PREFIX}/scripts/"*.sh 2>/dev/null || true
fi
[[ -f "${SCRIPT_DIR}/BUILD_INFO.txt" ]] && cp -f "${SCRIPT_DIR}/BUILD_INFO.txt" "${PREFIX}/BUILD_INFO.txt"

if [[ "${INSTALL_SYSTEMD:-0}" == "1" ]]; then
  mkdir -p "${SYSTEMD_PATH}"
  cp -f "${PREFIX}/systemd/pxdesign.service" "${SYSTEMD_PATH}/pxdesign.service"
  [[ -f "${PREFIX}/systemd/pxdesign-oneshot.service" ]] && cp -f "${PREFIX}/systemd/pxdesign-oneshot.service" "${SYSTEMD_PATH}/pxdesign-oneshot.service"
  if [[ "${SYSTEMD_PATH}" == *"/systemd/user"* ]]; then
    systemctl --user daemon-reload
    systemctl --user enable pxdesign.service || true
    echo "[install_${APP_NAME}] enabled --user pxdesign.service; oneshot 模板已拷贝"
  else
    systemctl daemon-reload
    systemctl enable pxdesign.service || true
    echo "[install_${APP_NAME}] enabled pxdesign.service; oneshot 模板已拷贝"
  fi
else
  echo "[install_${APP_NAME}] skip systemd (set INSTALL_SYSTEMD=1)"
fi

echo "[install_${APP_NAME}] done. primary=${PREFIX}/bin/pxdesignd cli=${PREFIX}/bin/pxdesign-run"
