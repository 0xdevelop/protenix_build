#!/bin/bash
# 在独立 prefix 用 uv 建 Python 3.14 venv，安装 PXDesign 及其依赖链。
# 可用场景：
#   1) 仓库内：./build.sh pxdesign 或本脚本（经 scripts/repo_src_defaults.sh 定位 submodule）
#   2) 发布包内：包已含 src/ + deps/ + patches/，只使用包内文件（仍需联网拉 pip 依赖与权重）
#
# 运行时需：LAYERNORM_TYPE=torch、TOOL_WEIGHTS_ROOT、PROTENIX_DATA_ROOT_DIR，
# 以及 pipeline 参数 --num_workers 0 --use_fast_ln False --load_checkpoint_dir <数据目录>/release_data/checkpoint
#
# PXDESIGN_DATA：权重与数据目录（默认 <prefix>）。缺失的权重从上游官方地址下载；
# 设 WEIGHTS_REUSE_FROM=<已有 prefix 根> 时改为从 <根>/pxdesign 硬链接。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/weights_reuse.sh"
if [[ -f "${ROOT}/scripts/repo_src_defaults.sh" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/scripts/repo_src_defaults.sh"
fi

if [[ -n "${PREFIX_ROOT:-}" ]]; then
  PREFIX="${PXDESIGN_PREFIX:-${PREFIX_ROOT}/pxdesign}"
else
  PREFIX="${PXDESIGN_PREFIX:-${ROOT}/prefix/pxdesign}"
fi

PINNED_PROTENIX_REF="${PINNED_PROTENIX_REF:-v0.5.0+pxd}"
PXDBENCH_REF="${PXDBENCH_REF:-v0.1.2}"
COLABDESIGN_REF="${COLABDESIGN_REF:-main}"
OVERRIDES="${PXDESIGN_OVERRIDES:-${ROOT}/deps/pxdesign.txt}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
VENV="${PREFIX}/venv"
LOG_DIR="${PREFIX}/logs"
TAG="[install_prefix_pxdesign]"

die() { echo "${TAG} FAIL: $*" >&2; exit 1; }

resolve_src() {
  if [[ -n "${PXDESIGN_SRC:-}" ]]; then
    SRC="${PXDESIGN_SRC}"
    return 0
  fi
  if [[ -f "${ROOT}/src/SRC_SHA" && -f "${ROOT}/src/pxdesign/setup.py" ]]; then
    SRC="${ROOT}/src/pxdesign"
    return 0
  fi
  if [[ -n "${REPO_PXDESIGN_SRC:-}" && -f "${REPO_PXDESIGN_SRC}/setup.py" ]]; then
    SRC="${REPO_PXDESIGN_SRC}"
    return 0
  fi
  die "no PXDesign source (set PXDESIGN_SRC, or use a release package with src/pxdesign)"
}

resolve_src_sha() {
  if [[ -n "${SRC_SHA:-}" ]]; then
    return 0
  fi
  if [[ -f "${ROOT}/src/SRC_SHA" ]]; then
    SRC_SHA="$(tr -d '[:space:]' < "${ROOT}/src/SRC_SHA")"
    [[ -n "${SRC_SHA}" ]] || die "empty ${ROOT}/src/SRC_SHA"
    return 0
  fi
  if git -C "${SRC}" rev-parse --verify HEAD >/dev/null 2>&1; then
    SRC_SHA="$(git -C "${SRC}" rev-parse HEAD)"
    return 0
  fi
  die "cannot determine source SHA for ${SRC}"
}

stage_upstream_src() {
  if [[ -f "${STAGE}/setup.py" ]]; then
    return 0
  fi
  rm -rf "${STAGE}.partial"
  mkdir -p "${STAGE}.partial"
  if git -C "${SRC}" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "${SRC}" archive --format=tar HEAD | tar -x -C "${STAGE}.partial"
  else
    cp -a "${SRC}/." "${STAGE}.partial/"
  fi
  mv "${STAGE}.partial" "${STAGE}"
}

run_step() {
  local step="$1"; shift
  local log="${LOG_DIR}/install_${step}.log"
  echo "${TAG} step=${step}: $*"
  local rc=0
  "$@" >"${log}" 2>&1 || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "${TAG} FAIL step=${step} rc=${rc} log=${log}" >&2
    grep -E "Failed to (build|download|prepare)|No solution found|Because |error:|Error" "${log}" | head -20 >&2 || true
    echo "${TAG} ---- last 40 lines of ${log} ----" >&2
    tail -n 40 "${log}" >&2
    exit 1
  fi
}

UV_BIN="${UV:-}"
if [[ -z "${UV_BIN}" ]]; then
  if command -v uv >/dev/null 2>&1; then UV_BIN="$(command -v uv)"
  elif [[ -x "${HOME}/.local/bin/uv" ]]; then UV_BIN="${HOME}/.local/bin/uv"
  else die "uv not found"; fi
fi
[[ -f "${OVERRIDES}" ]] || die "override file missing: ${OVERRIDES}"
resolve_src
[[ -f "${SRC}/setup.py" ]] || die "PXDesign setup.py missing under ${SRC}"
[[ -x "${CUDA_HOME}/bin/nvcc" ]] || die "nvcc not found under CUDA_HOME=${CUDA_HOME}"

DATA="${PXDESIGN_DATA:-${PREFIX}}"
mkdir -p "${PREFIX}"/{logs,conf,src} "${DATA}"/{release_data/checkpoint,tool_weights,protenix_data}
resolve_src_sha
echo "${TAG} prefix=${PREFIX} src=${SRC}@${SRC_SHA:0:12} protenix=${PINNED_PROTENIX_REF} pxdbench=${PXDBENCH_REF}"

if [[ -x "${VENV}/bin/python" ]]; then
  v="$("${VENV}/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  if [[ "${v}" != "3.14" ]]; then
    mv "${VENV}" "${VENV}.py${v/./}.bak.$(date +%Y%m%d%H%M%S)"
    echo "${TAG} moved old python ${v} venv aside"
  fi
fi
[[ -x "${VENV}/bin/python" ]] || run_step venv "${UV_BIN}" venv --python 3.14 --seed "${VENV}"
export VIRTUAL_ENV="${VENV}"

run_step torch "${UV_BIN}" pip install --python "${VENV}/bin/python" \
  --index-url "${PYPI_INDEX_URL}" --extra-index-url "${TORCH_INDEX_URL}" --index-strategy unsafe-best-match \
  "torch==2.14.1+cu130"
run_step build_tools "${UV_BIN}" pip install --python "${VENV}/bin/python" --index-url "${PYPI_INDEX_URL}" \
  setuptools wheel ninja packaging cython "numpy>=2.0,<2.5"

STAGE="${PREFIX}/src/pxdesign-${SRC_SHA:0:12}"
stage_upstream_src

STAGE_PATCH="${ROOT}/patches/pxdesign-argparse-percent.patch"
[[ -f "${STAGE_PATCH}" ]] || die "patch missing: ${STAGE_PATCH}"
if patch -p1 -d "${STAGE}" -R -s -f --dry-run -i "${STAGE_PATCH}" >/dev/null 2>&1; then
  echo "${TAG} pxdesign stage patch already applied"
else
  patch -p1 -d "${STAGE}" -N -f -i "${STAGE_PATCH}" || die "apply ${STAGE_PATCH} failed"
fi

REQS=(
  -r "${STAGE}/requirements.txt"
  "protenix @ git+https://github.com/bytedance/Protenix.git@${PINNED_PROTENIX_REF}"
  "pxdbench @ git+https://github.com/bytedance/PXDesignBench.git@${PXDBENCH_REF}"
  "colabdesign @ git+https://github.com/sokrypton/ColabDesign.git@${COLABDESIGN_REF}"
  "jax[cuda13]"
  einops natsort dm-tree posix_ipc
  -e "${STAGE}"
)
run_step deps env DS_BUILD_OPS=0 "${UV_BIN}" pip install --python "${VENV}/bin/python" \
  --override "${OVERRIDES}" \
  --index-url "${PYPI_INDEX_URL}" --extra-index-url "${TORCH_INDEX_URL}" --index-strategy unsafe-best-match \
  --no-build-isolation-package deepspeed \
  "${REQS[@]}"

PATCH_FILE="${ROOT}/patches/pxdbench-json-float.patch"
[[ -f "${PATCH_FILE}" ]] || die "patch missing: ${PATCH_FILE}"
SITE_PKGS="$("${VENV}/bin/python" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])')"
if patch -p1 -d "${SITE_PKGS}" -R -s -f --dry-run -i "${PATCH_FILE}" >/dev/null 2>&1; then
  echo "${TAG} pxdbench patch already applied"
else
  run_step patch_pxdbench patch -p1 -d "${SITE_PKGS}" -N -f -i "${PATCH_FILE}"
fi

export PATH="${VENV}/bin:${CUDA_HOME}/bin:${PATH}"
export LAYERNORM_TYPE="${LAYERNORM_TYPE:-torch}"
run_step verify_import "${VENV}/bin/python" -c '
import torch, jax, jax.numpy as jnp, colabdesign, protenix, pxdbench, pxdesign
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
print("torch", torch.__version__, torch.version.cuda, torch.cuda.get_device_name(0))
print("jax", jax.__version__, jax.devices())
assert any(d.platform == "gpu" for d in jax.devices()), "jax sees no GPU"
print("jax matmul", float((jnp.ones((256,256)) @ jnp.ones((256,256))).sum()))
'
cat "${LOG_DIR}/install_verify_import.log"
[[ -x "${VENV}/bin/pxdesign" ]] || die "pxdesign console_script missing"
run_step verify_cli "${VENV}/bin/pxdesign" pipeline --help
"${UV_BIN}" pip freeze --python "${VENV}/bin/python" > "${PREFIX}/conf/pip-freeze.txt"

CKPT_DIR="${DATA}/release_data/checkpoint"
TW="${DATA}/tool_weights"
CCD="${DATA}/protenix_data"
if [[ -n "${WEIGHTS_REUSE_FROM:-}" ]]; then
  REUSE_P="${WEIGHTS_REUSE_FROM}/pxdesign"
  [[ -d "${REUSE_P}" ]] || die "WEIGHTS_REUSE_FROM pxdesign missing: ${REUSE_P}"
  echo "${TAG} reuse weights from ${REUSE_P}"
  for tree in release_data/checkpoint tool_weights protenix_data; do
    [[ -d "${REUSE_P}/${tree}" ]] || die "reuse tree missing: ${REUSE_P}/${tree}"
    seed_tree_verified "${REUSE_P}/${tree}" "${DATA}/${tree}"
  done
fi

# 缺什么下什么（地址同上游 pxdesign/utils/infer.py 与 download_tool_weights.sh）
fetch() {
  local url="$1" dst="$2"
  [[ -s "${dst}" ]] && return 0
  echo "${TAG} download ${url}"
  mkdir -p "$(dirname "${dst}")"
  curl -fL --retry 3 -o "${dst}.part" "${url}" || { rm -f "${dst}.part"; die "download failed: ${url}"; }
  mv "${dst}.part" "${dst}"
}
TOS="https://pxdesign.tos-cn-beijing.volces.com"
for m in pxdesign_v0.1.0 protenix_base_default_v0.5.0 protenix_mini_default_v0.5.0 protenix_mini_tmpl_v0.5.0; do
  fetch "${TOS}/release_model/${m}.pt" "${CKPT_DIR}/${m}.pt"
done
for f in components.v20240608.cif components.v20240608.cif.rdkit_mol.pkl clusters-by-entity-40.txt; do
  fetch "${TOS}/release_data/${f}" "${CCD}/${f}"
done
if [[ ! -s "${TW}/af2/params_model_1.npz" || ! -s "${TW}/af2/params_model_1_ptm.npz" ]]; then
  # 只解出 PXDesign 必需的两个 AF2 参数文件，不落地 5GB 的 tar
  echo "${TAG} download AlphaFold2 params (stream, extract params_model_1{,_ptm}.npz)"
  mkdir -p "${TW}/af2.part"
  curl -fL --retry 3 https://storage.googleapis.com/alphafold/alphafold_params_2022-12-06.tar \
    | tar -x -C "${TW}/af2.part" params_model_1.npz params_model_1_ptm.npz LICENSE \
    || { rm -rf "${TW}/af2.part"; die "AF2 params download failed"; }
  mkdir -p "${TW}/af2"
  mv -f "${TW}/af2.part"/* "${TW}/af2/"
  rmdir "${TW}/af2.part"
fi
if [[ ! -d "${TW}/mpnn/vanilla_model_weights" ]]; then
  echo "${TAG} download ProteinMPNN weights (git clone --depth 1)"
  MPNN_TMP="$(mktemp -d)"
  git clone -q --depth 1 https://github.com/dauparas/ProteinMPNN.git "${MPNN_TMP}" \
    || { rm -rf "${MPNN_TMP}"; die "ProteinMPNN clone failed"; }
  mkdir -p "${TW}/mpnn"
  for d in ca_model_weights soluble_model_weights vanilla_model_weights; do
    [[ -d "${TW}/mpnn/${d}" ]] || cp -r "${MPNN_TMP}/${d}" "${TW}/mpnn/${d}"
  done
  rm -rf "${MPNN_TMP}"
fi
for f in "${CKPT_DIR}/pxdesign_v0.1.0.pt" "${TW}/af2/params_model_1.npz" "${TW}/af2/params_model_1_ptm.npz" \
         "${CCD}/components.v20240608.cif"; do
  [[ -s "${f}" ]] || die "missing ${f}"
done

echo "${TAG} status=ok src_sha=${SRC_SHA}"
