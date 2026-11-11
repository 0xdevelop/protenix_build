#!/bin/bash
# 目标机执行：在独立 prefix（prefix/pxdesign）用 uv 建 Python 3.14 venv，安装 PXDesign 及其官方依赖链：
#   Protenix@v0.5.0+pxd（官方钉死版本，不用 build_srcs/protenix 最新 submodule；两个 venv 保持独立）、
#   PXDesignBench@v0.1.2、ColabDesign、JAX（CUDA 13 插件）、torch 2.14.1+cu130。
# 不用 conda / Docker / Python 3.11；版本覆盖见 constraints/pxdesign-py314-cu130.txt。
# 失败即非零退出并打印阶段与报错；不做任何“无 GPU 跳过”。
# 运行时（GB10 + Python 3.14 实测，见 docs/acceptance_pxdesign_gb10.md）必须：
#   export LAYERNORM_TYPE=torch TOOL_WEIGHTS_ROOT=<prefix>/tool_weights PROTENIX_DATA_ROOT_DIR=<prefix>/protenix_data
#   pxdesign pipeline ... --num_workers 0 --use_fast_ln False --load_checkpoint_dir <prefix>/release_data/checkpoint
#
# 用法：
#   bash scripts/install_prefix_pxdesign.sh
# 可选环境变量：PXDESIGN_PREFIX、PXDESIGN_SRC、PINNED_PROTENIX_REF(默认 v0.5.0+pxd)、
#   PXDBENCH_REF(默认 v0.1.2)、COLABDESIGN_REF(默认 main)、UV、CUDA_HOME、TORCH_INDEX_URL、PYPI_INDEX_URL
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PXDESIGN_PREFIX:-${ROOT}/prefix/pxdesign}"
SRC="${PXDESIGN_SRC:-${ROOT}/build_srcs/pxdesign}"
PINNED_PROTENIX_REF="${PINNED_PROTENIX_REF:-v0.5.0+pxd}"
PXDBENCH_REF="${PXDBENCH_REF:-v0.1.2}"
COLABDESIGN_REF="${COLABDESIGN_REF:-main}"
OVERRIDES="${PXDESIGN_OVERRIDES:-${ROOT}/constraints/pxdesign-py314-cu130.txt}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
VENV="${PREFIX}/venv"
LOG_DIR="${PREFIX}/logs"
TAG="[install_prefix_pxdesign]"

die() { echo "${TAG} FAIL: $*" >&2; exit 1; }
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
git -C "${SRC}" rev-parse --verify HEAD >/dev/null 2>&1 || die "src is not a git work tree: ${SRC}"
[[ -x "${CUDA_HOME}/bin/nvcc" ]] || die "nvcc not found under CUDA_HOME=${CUDA_HOME}"

mkdir -p "${PREFIX}"/{release_data/checkpoint,tool_weights,protenix_data,logs,conf,bin,src}
SRC_SHA="$(git -C "${SRC}" rev-parse HEAD)"
echo "${TAG} prefix=${PREFIX} src=${SRC}@${SRC_SHA:0:12} protenix=${PINNED_PROTENIX_REF} pxdbench=${PXDBENCH_REF}"

# 1) venv：必须是 3.14；旧的非 3.14 venv 改名保留（不删除）
if [[ -x "${VENV}/bin/python" ]]; then
  v="$("${VENV}/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  if [[ "${v}" != "3.14" ]]; then
    mv "${VENV}" "${VENV}.py${v/./}.bak.$(date +%Y%m%d%H%M%S)"
    echo "${TAG} moved old python ${v} venv aside"
  fi
fi
[[ -x "${VENV}/bin/python" ]] || run_step venv "${UV_BIN}" venv --python 3.14 --seed "${VENV}"
export VIRTUAL_ENV="${VENV}"

# 2) torch 先装（deepspeed 源码构建需要）
run_step torch "${UV_BIN}" pip install --python "${VENV}/bin/python" \
  --index-url "${PYPI_INDEX_URL}" --extra-index-url "${TORCH_INDEX_URL}" --index-strategy unsafe-best-match \
  "torch==2.14.1+cu130"
run_step build_tools "${UV_BIN}" pip install --python "${VENV}/bin/python" --index-url "${PYPI_INDEX_URL}" \
  setuptools wheel ninja packaging cython "numpy>=2.0,<2.5"

# 3) PXDesign 源码快照（不在 submodule 工作树内构建）。
#    以 editable 方式安装这份快照（与上游 `pip install -e .` 一致）：上游 pxdesign/configs 等目录没有 __init__.py，
#    非 editable 安装时 find_packages 会漏掉它们（实测 ModuleNotFoundError: pxdesign.configs）。
STAGE="${PREFIX}/src/pxdesign-${SRC_SHA:0:12}"
if [[ ! -f "${STAGE}/setup.py" ]]; then
  rm -rf "${STAGE}.partial"; mkdir -p "${STAGE}.partial"
  git -C "${SRC}" archive --format=tar HEAD | tar -x -C "${STAGE}.partial"
  mv "${STAGE}.partial" "${STAGE}"
fi

# 3b) 快照上的 Python 3.14 兼容补丁（只改 prefix 里的快照，不改 submodule）：
#     3.14 的 argparse 会在 add_argument 时校验 help 字符串，上游 pxd_server/*.py 的 "0-5%, 5-15%" 未转义，
#     报 ValueError: badly formed help string，pipeline 最后画难度图那步失败（rc=1）。已打过则跳过。
STAGE_PATCH="${ROOT}/constraints/pxdesign-py314-argparse-percent.patch"
if patch -p1 -d "${STAGE}" -R -s -f --dry-run -i "${STAGE_PATCH}" >/dev/null 2>&1; then
  echo "${TAG} pxdesign stage patch already applied"
else
  patch -p1 -d "${STAGE}" -N -f -i "${STAGE_PATCH}" || die "apply ${STAGE_PATCH} failed"
fi

# 4) 全部依赖一次解析安装（上游 requirements.txt + install.sh 里逐个 pip 的包）
REQS=(
  -r "${SRC}/requirements.txt"
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

# 4b) pxdbench 运行期补丁（只改 venv 内已安装的 pxdbench，不改 submodule）：
#     AF2 子进程把 np.float32（biopython 坐标算出的 RMSD）直接 json.dump，报 "Object of type float32 is not JSON serializable"，
#     pipeline 随即失败。补丁只给 json.dump 加 default=float。已打过则跳过。
PATCH_FILE="${ROOT}/constraints/pxdbench-af2-json-float32.patch"
SITE_PKGS="$("${VENV}/bin/python" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])')"
if patch -p1 -d "${SITE_PKGS}" -R -s -f --dry-run -i "${PATCH_FILE}" >/dev/null 2>&1; then
  echo "${TAG} pxdbench patch already applied"
else
  run_step patch_pxdbench patch -p1 -d "${SITE_PKGS}" -N -f -i "${PATCH_FILE}"
fi

# 5) 校验（与上游 install.sh 的 sanity check 同一组模块 + GPU 可见性）
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
echo "${TAG} status=ok src_sha=${SRC_SHA}"
