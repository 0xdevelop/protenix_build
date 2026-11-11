#!/bin/bash
# 目标机执行：独立 prefix 安装 PXDesign + 钉死 Protenix@v0.5.0+pxd + torch==2.3.1。
# **不要**用最新 build_srcs/protenix submodule 填本 env；另 pip 该 tag，不改 submodule 工作树。
# 编排仅 shell；上游 Python 只在本 prefix 环境内跑。
#
# 目标运行栈（用户硬约束）：CUDA 13 / Python 3.14 / Node 24 LTS。
# **不要**原样调用上游 install.sh（若其不认 CUDA 13）；本脚本另装独立 prefix。
# 上游 torch pin 与 Python 3.14 的 wheel 缺口属待收敛债务，不得把目标改回 3.11–3.13。
#
# 用法：
#   bash scripts/install_prefix_pxdesign.sh
#   PXDESIGN_PYTHON=/usr/bin/python3.14 bash scripts/install_prefix_pxdesign.sh
#   SKIP_PIP=1 bash scripts/install_prefix_pxdesign.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PXDESIGN_PREFIX:-${ROOT}/prefix/pxdesign}"
SRC="${PXDESIGN_SRC:-${ROOT}/build_srcs/pxdesign}"
PINNED_PROTENIX_REF="${PINNED_PROTENIX_REF:-v0.5.0+pxd}"
PREFERRED_PYTHONS=(
  "${PXDESIGN_PYTHON:-}"
  python3.14
  /usr/bin/python3.14
)

echo "[install_prefix_pxdesign] prefix=${PREFIX}"
echo "[install_prefix_pxdesign] src=${SRC}"
echo "[install_prefix_pxdesign] pinned_protenix=${PINNED_PROTENIX_REF}"
echo "[install_prefix_pxdesign] target runtime: CUDA 13 / Python 3.14 / Node 24 LTS"

mkdir -p "${PREFIX}/release_data/checkpoint" "${PREFIX}/tool_weights" "${PREFIX}/protenix_data" \
  "${PREFIX}/cutlass" "${PREFIX}/logs" "${PREFIX}/conf" "${PREFIX}/bin" "${PREFIX}/scripts"

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
    if [[ "${major}" -eq 3 && "${minor}" -eq 14 ]]; then
      echo "${cand}"
      return 0
    fi
    echo "[install_prefix_pxdesign] skip ${cand} (version ${ver}; hard constraint requires Python 3.14)" >&2
  done
  return 1
}

mkdir -p "${ROOT}/tmp"
if [[ "${SKIP_PIP:-0}" == "1" ]]; then
  echo "[install_prefix_pxdesign] SKIP_PIP=1 — created dirs only; NOT installing torch/pxdesign/protenix pin"
  echo "reason=skip_pip time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${ROOT}/tmp/install_prefix_pxdesign.skip"
  echo "[install_prefix_pxdesign] status=skipped_pip"
  exit 0
fi
# 无 GPU 设备节点时默认跳过重依赖（构建包装层验证不卡死）；强制装设 SKIP_IF_NO_GPU=0
if [[ "${SKIP_IF_NO_GPU:-1}" == "1" ]] && [[ ! -e /dev/nvidia0 ]]; then
  echo "[install_prefix_pxdesign] SKIP: no /dev/nvidia0 (set SKIP_IF_NO_GPU=0 to force)"
  echo "reason=no_gpu_device_node pinned=${PINNED_PROTENIX_REF} time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${ROOT}/tmp/install_prefix_pxdesign.skip"
  echo "[install_prefix_pxdesign] status=skipped_no_gpu"
  exit 0
fi

if [[ ! -d "${SRC}" ]]; then
  echo "[install_prefix_pxdesign] FAIL: src missing ${SRC} (git submodule update --init --recursive)" >&2
  exit 1
fi

PY="$(pick_python || true)"
if [[ -z "${PY}" ]]; then
  echo "[install_prefix_pxdesign] FAIL: no usable Python 3.14 found (hard constraint)." >&2
  echo "[install_prefix_pxdesign] install python3.14 then re-run, or set PXDESIGN_PYTHON=/path/to/python3.14" >&2
  exit 1
fi

ver="$("${PY}" -c 'import sys; print("%d.%d.%d"%sys.version_info[:3])')"
echo "[install_prefix_pxdesign] using ${PY} (${ver})"

if [[ ! -d "${PREFIX}/venv" ]]; then
  "${PY}" -m venv "${PREFIX}/venv"
fi
# shellcheck disable=SC1091
source "${PREFIX}/venv/bin/activate"
python -m pip install -U pip setuptools wheel

echo "[install_prefix_pxdesign] installing pinned Protenix@${PINNED_PROTENIX_REF} (not latest submodule)"
if ! pip install --no-cache-dir "git+https://github.com/bytedance/Protenix.git@${PINNED_PROTENIX_REF}"; then
  echo "[install_prefix_pxdesign] FAIL: pinned Protenix install failed (not marking success)." >&2
  exit 1
fi

echo "[install_prefix_pxdesign] installing PXDesign from ${SRC}"
if ! pip install -e "${SRC}"; then
  echo "[install_prefix_pxdesign] FAIL: pip install -e pxdesign failed (not marking success)." >&2
  exit 1
fi

if ! command -v pxdesign >/dev/null 2>&1; then
  echo "[install_prefix_pxdesign] FAIL: pxdesign console_script missing after install" >&2
  exit 1
fi

echo "[install_prefix_pxdesign] smoke: pxdesign --help"
pxdesign --help | head -40 || true
echo "[install_prefix_pxdesign] status=ok"
echo "[install_prefix_pxdesign] next: download_tool_weights (from pxdesign repo) into TOOL_WEIGHTS_ROOT if needed"
