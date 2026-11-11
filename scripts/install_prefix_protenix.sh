#!/bin/bash
# 目标机执行：在独立 prefix 安装最新 Protenix submodule 运行栈（torch 2.7.1 链）。
# 编排仅 shell；上游 Python 只在本 prefix venv 内跑。
#
# 宿主 CUDA 13 + prefix 内 cu12 torch wheel；产品 venv 优先 3.11/3.12（可到 3.13）。
# 禁止用宿主 3.14 装钉死 torch==2.7.1（无 cp314 wheel）。Node 不参与本链。
#
# 用法：
#   bash scripts/install_prefix_protenix.sh
#   PROTENIX_PYTHON=/usr/bin/python3.12 bash scripts/install_prefix_protenix.sh
#   SKIP_PIP=1 bash scripts/install_prefix_protenix.sh   # 只建目录，不装依赖
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PROTENIX_PREFIX:-${ROOT}/prefix/protenix}"
SRC="${PROTENIX_SRC:-${ROOT}/build_srcs/protenix}"
PREFERRED_PYTHONS=(
  "${PROTENIX_PYTHON:-}"
  python3.11
  python3.12
  python3.13
  /usr/bin/python3.11
  /usr/bin/python3.12
  /usr/bin/python3.13
)

echo "[install_prefix_protenix] prefix=${PREFIX}"
echo "[install_prefix_protenix] src=${SRC}"
echo "[install_prefix_protenix] note: host may have python3.14, but product env MUST be 3.11-3.13 (torch 2.7.1 has no cp314 wheel)"

mkdir -p "${PREFIX}/data" "${PREFIX}/cutlass" "${PREFIX}/logs" "${PREFIX}/conf" "${PREFIX}/bin" "${PREFIX}/scripts"

pick_python() {
  local cand ver major minor
  for cand in "${PREFERRED_PYTHONS[@]}"; do
    [[ -z "${cand}" ]] && continue
    if ! command -v "${cand}" >/dev/null 2>&1 && [[ ! -x "${cand}" ]]; then
      continue
    fi
    ver="$("${cand}" -c 'import sys; print("%d.%d"%sys.version_info[:2])' 2>/dev/null || true)"
    [[ -z "${ver}" ]] && continue
    major="${ver%%.*}"
    minor="${ver##*.}"
    if [[ "${major}" -eq 3 && "${minor}" -ge 11 && "${minor}" -le 13 ]]; then
      echo "${cand}"
      return 0
    fi
    echo "[install_prefix_protenix] skip ${cand} (version ${ver}; need 3.11-3.13, not 3.14+)" >&2
  done
  return 1
}

mkdir -p "${ROOT}/tmp"
if [[ "${SKIP_PIP:-0}" == "1" ]]; then
  echo "[install_prefix_protenix] SKIP_PIP=1 — created dirs only; NOT installing torch/protenix"
  echo "reason=skip_pip time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${ROOT}/tmp/install_prefix_protenix.skip"
  echo "[install_prefix_protenix] status=skipped_pip"
  exit 0
fi
# 无 GPU 设备节点时默认跳过重依赖（构建包装层验证不卡死）；强制装设 SKIP_IF_NO_GPU=0
if [[ "${SKIP_IF_NO_GPU:-1}" == "1" ]] && [[ ! -e /dev/nvidia0 ]]; then
  echo "[install_prefix_protenix] SKIP: no /dev/nvidia0 (set SKIP_IF_NO_GPU=0 to force)"
  echo "reason=no_gpu_device_node time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${ROOT}/tmp/install_prefix_protenix.skip"
  echo "[install_prefix_protenix] status=skipped_no_gpu"
  exit 0
fi

if [[ ! -d "${SRC}" ]]; then
  echo "[install_prefix_protenix] FAIL: src missing ${SRC} (git submodule update --init --recursive)" >&2
  exit 1
fi

PY="$(pick_python || true)"
if [[ -z "${PY}" ]]; then
  echo "[install_prefix_protenix] FAIL: no usable Python 3.11-3.13 found." >&2
  echo "[install_prefix_protenix] host python3.14 cannot install torch==2.7.1 (no cp314 wheel)." >&2
  echo "[install_prefix_protenix] install python3.12 (or 3.11/3.13) then re-run; do NOT force 3.14." >&2
  exit 1
fi

ver="$("${PY}" -c 'import sys; print("%d.%d.%d"%sys.version_info[:3])')"
echo "[install_prefix_protenix] using ${PY} (${ver})"

if [[ ! -d "${PREFIX}/venv" ]]; then
  "${PY}" -m venv "${PREFIX}/venv"
fi
# shellcheck disable=SC1091
source "${PREFIX}/venv/bin/activate"
python -m pip install -U pip setuptools wheel

echo "[install_prefix_protenix] installing from ${SRC} (editable). This pulls torch==2.7.1 etc."
if ! pip install -e "${SRC}"; then
  echo "[install_prefix_protenix] FAIL: pip install -e failed (not marking success)." >&2
  exit 1
fi

if ! command -v protenix >/dev/null 2>&1; then
  echo "[install_prefix_protenix] FAIL: protenix console_script missing after install" >&2
  exit 1
fi

echo "[install_prefix_protenix] smoke: protenix --help"
protenix --help | head -40
echo "[install_prefix_protenix] status=ok"
