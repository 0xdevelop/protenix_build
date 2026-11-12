#!/bin/bash
# 目标机执行：在独立 prefix 用 uv 建 Python 3.14 venv，装 torch(cu130) + 最新 Protenix submodule。
# 目标运行栈（用户硬约束）：CUDA 13 / Python 3.14 / Node 24 LTS；不用 conda / Docker。
# 编排只用 shell；上游 Python 只在 prefix venv 内运行。不修改 submodule：
#   源码通过 `git archive <submodule HEAD>` 导出到 prefix/src 后再做非 editable 安装，
#   构建产生的 build/、*.egg-info 不会落到 build_srcs/protenix 工作树里。
#
# 依赖版本覆盖：constraints/py314-cu130.txt（uv --override 语义，每条有原因注释）。
# 失败策略：任一步失败立即非零退出，并打印阶段/包名与报错日志尾部；没有任何“无 GPU 跳过”逻辑。
#
# 用法：
#   bash scripts/install_prefix_protenix.sh
# 可选环境变量：
#   PREFIX_ROOT       若设，默认 prefix 为 <PREFIX_ROOT>/protenix（仍可被 PROTENIX_PREFIX 覆盖）
#   PROTENIX_PREFIX   默认 <PREFIX_ROOT|/repo/prefix>/protenix
#   PROTENIX_SRC      默认 <repo>/build_srcs/protenix（必须是 git 工作树）
#   PROTENIX_PYTHON   默认 3.14（传给 uv venv --python）
#   UV                默认 PATH 中的 uv，其次 ~/.local/bin/uv
#   CUDA_HOME         默认 /usr/local/cuda-13.0
#   TORCH_INDEX_URL   默认 https://download.pytorch.org/whl/cu130
#   PYPI_INDEX_URL    默认 https://pypi.org/simple（国内可用 https://mirrors.aliyun.com/pypi/simple）
#   RECREATE_VENV=1   删除并重建 prefix/venv
#   LAYERNORM_TYPE    默认 torch（上游文档的回退开关，见下方说明）
#   PROTENIX_MODEL    模型版本单一切换点，默认取 conf/protenix.env，再默认 protenix_base_default_v1.0.0。
#                     脚本只会下载非 v2 的公开权重；PROTENIX_MODEL=protenix-v2 且本地没有
#                     $PROTENIX_ROOT_DIR/checkpoint/protenix-v2.pt 时直接失败（v2 需授权权重，官方地址 403，不尝试下载）。
#   SKIP_WEIGHTS=1    不预取权重/CCD 缓存（推理时上游会自行下载）
#   WEIGHTS_REUSE_FROM  已校验 prefix 根（含 protenix/data）；硬链接/拷贝并校 size（拷贝再校 sha256）
#
# 关于 fast_layernorm（上游自定义 CUDA 内核，import 时 JIT 编译）：
#   在 torch 2.14 + CUDA 13 上编译失败，已核实原因：上游 torch_ext_compile.py 固定传 -std=c++17，
#   而 torch 2.14 头文件要求 C++20（"#error C++20 or later compatible compiler is required to use PyTorch."）；
#   且其 gencode 列表最高 sm_100，不含 GB10 的 sm_121。不改 submodule 的前提下，
#   采用上游 docs/kernels.md 记载的回退：LAYERNORM_TYPE=torch（原生 PyTorch layernorm）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/weights_reuse.sh"
if [[ -n "${PREFIX_ROOT:-}" ]]; then
  PREFIX="${PROTENIX_PREFIX:-${PREFIX_ROOT}/protenix}"
else
  PREFIX="${PROTENIX_PREFIX:-${ROOT}/prefix/protenix}"
fi
SRC="${PROTENIX_SRC:-${ROOT}/build_srcs/protenix}"
PY_REQ="${PROTENIX_PYTHON:-3.14}"
OVERRIDES="${PROTENIX_OVERRIDES:-${ROOT}/constraints/py314-cu130.txt}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.org/simple}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
VENV="${PREFIX}/venv"
LOG_DIR="${PREFIX}/logs"
TAG="[install_prefix_protenix]"

TORCH_SPEC=(torch==2.14.1+cu130 torchvision==0.29.1+cu130)
# override 只能替换已有依赖、不能新增：上游要求的 cuequivariance-ops-torch-cu12 被 override 移除后，
# cu13 版必须在这里显式安装（否则 cuequivariance_ops_torch 缺失，推理在三角注意力处 ImportError）。
EXTRA_REQS=(cuequivariance-ops-torch-cu13)
# 只有 sdist、需要本机源码编译的包；deepspeed 的 setup.py 需要 import torch，关闭其构建隔离。
NO_BUILD_ISOLATION_PKGS=(deepspeed)

die() { echo "${TAG} FAIL: $*" >&2; exit 1; }

# run_step <阶段名> <命令...>：命令输出写入日志；失败时打印包名/报错尾部并非零退出。
run_step() {
  local step="$1"; shift
  local log="${LOG_DIR}/install_${step}.log"
  echo "${TAG} step=${step}: $*"
  local rc=0
  "$@" >"${log}" 2>&1 || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "${TAG} FAIL step=${step} rc=${rc} log=${log}" >&2
    # uv 报错里会带 "Failed to build `pkg`" / "Because pkg..." 等包名信息
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
  else die "uv not found (install: curl -LsSf https://astral.sh/uv/install.sh | sh)"; fi
fi

[[ -f "${OVERRIDES}" ]] || die "override file missing: ${OVERRIDES}"
git -C "${SRC}" rev-parse --verify HEAD >/dev/null 2>&1 || die "src is not a git work tree: ${SRC} (git submodule update --init --recursive)"
[[ -x "${CUDA_HOME}/bin/nvcc" ]] || die "nvcc not found under CUDA_HOME=${CUDA_HOME} (CUDA 13 toolkit required; fast_layernorm / deepspeed 编译需要)"
command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not found (NVIDIA driver required)"

mkdir -p "${PREFIX}"/{data,logs,conf,bin,scripts,src}
SRC_SHA="$(git -C "${SRC}" rev-parse HEAD)"
echo "${TAG} prefix=${PREFIX}"
echo "${TAG} src=${SRC} @ ${SRC_SHA}"
echo "${TAG} uv=${UV_BIN} ($("${UV_BIN}" --version))"
echo "${TAG} cuda=$("${CUDA_HOME}/bin/nvcc" --version | grep -o 'release [0-9.]*')  torch_index=${TORCH_INDEX_URL} pypi_index=${PYPI_INDEX_URL}"

# conf/protenix.env：首次由模板渲染，已存在则不覆盖（后面权重路径依赖它）
ENV_TMPL="${ROOT}/example_files/protenix.env"
ENV_FILE="${PREFIX}/conf/protenix.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  [[ -f "${ENV_TMPL}" ]] || die "env template missing: ${ENV_TMPL}"
  sed "s|/opt/protenix_build/prefix/protenix|${PREFIX}|g" "${ENV_TMPL}" > "${ENV_FILE}"
  echo "${TAG} wrote ${ENV_FILE}"
fi
if [[ -z "${PROTENIX_MODEL:-}" ]]; then
  PROTENIX_MODEL="$(sed -n 's/^PROTENIX_MODEL=//p' "${ENV_FILE}" | tail -n1 | tr -d '"')"
fi
PROTENIX_MODEL="${PROTENIX_MODEL:-protenix_base_default_v1.0.0}"
DATA_ROOT="$(sed -n 's/^PROTENIX_ROOT_DIR=//p' "${ENV_FILE}" | tail -n1 | tr -d '"')"
DATA_ROOT="${DATA_ROOT:-${PREFIX}/data}"
CKPT="${DATA_ROOT}/checkpoint/${PROTENIX_MODEL}.pt"
echo "${TAG} PROTENIX_MODEL=${PROTENIX_MODEL} PROTENIX_ROOT_DIR=${DATA_ROOT}"

# 幂等早退：CLI + Python 3.14 + 模型权重 + 当前 submodule 快照目录仍在 → 不重装、不重下
READY_MARK="${PREFIX}/conf/install.ready"
STAGE="${PREFIX}/src/protenix-${SRC_SHA:0:12}"
if [[ "${RECREATE_VENV:-0}" != "1" && -x "${VENV}/bin/protenix" && -x "${VENV}/bin/python" && -s "${CKPT}" && -f "${STAGE}/setup.py" ]]; then
  PYV="$("${VENV}/bin/python" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
  if [[ "${PYV}" == 3.14.* ]]; then
    {
      echo "src_sha=${SRC_SHA}"
      echo "model=${PROTENIX_MODEL}"
      echo "python=${PYV}"
    } > "${READY_MARK}"
    echo "${TAG} skip: already ready python=${PYV} src_sha=${SRC_SHA:0:12} model=${PROTENIX_MODEL}"
    echo "${TAG} status=ok src_sha=${SRC_SHA} model=${PROTENIX_MODEL} skipped=1"
    exit 0
  fi
fi

# 1) venv（Python 3.14，uv 管理的解释器）
if [[ "${RECREATE_VENV:-0}" == "1" && -d "${VENV}" ]]; then
  rm -rf "${VENV}"
  rm -f "${READY_MARK}"
fi
if [[ ! -x "${VENV}/bin/python" ]]; then
  run_step venv "${UV_BIN}" venv --python "${PY_REQ}" --seed "${VENV}"
fi
PYV="$("${VENV}/bin/python" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
[[ "${PYV}" == 3.14.* ]] || die "venv python is ${PYV}, hard constraint requires 3.14 (RECREATE_VENV=1 to rebuild)"
echo "${TAG} venv=${VENV} python=${PYV}"
export VIRTUAL_ENV="${VENV}"

# 2) torch 栈先装（deepspeed 源码构建需要已安装的 torch）
run_step torch "${UV_BIN}" pip install --python "${VENV}/bin/python" \
  --index-url "${PYPI_INDEX_URL}" --extra-index-url "${TORCH_INDEX_URL}" --index-strategy unsafe-best-match \
  "${TORCH_SPEC[@]}"

# 3) 源码构建所需工具（无隔离构建的包要用到）
run_step build_tools "${UV_BIN}" pip install --python "${VENV}/bin/python" --index-url "${PYPI_INDEX_URL}" \
  setuptools wheel ninja packaging cython "numpy>=2.4.1,<2.5"

# 4) 导出 submodule 源码快照（不在 submodule 工作树里构建）
if [[ ! -f "${STAGE}/setup.py" ]]; then
  rm -rf "${STAGE}.partial"
  mkdir -p "${STAGE}.partial"
  git -C "${SRC}" archive --format=tar HEAD | tar -x -C "${STAGE}.partial"
  mv "${STAGE}.partial" "${STAGE}"
fi

# 5) Protenix + 依赖（上游 requirements 经 override 文件覆盖）
NBI_ARGS=()
for p in "${NO_BUILD_ISOLATION_PKGS[@]}"; do NBI_ARGS+=(--no-build-isolation-package "${p}"); done
run_step protenix env DS_BUILD_OPS=0 "${UV_BIN}" pip install --python "${VENV}/bin/python" \
  --override "${OVERRIDES}" \
  --index-url "${PYPI_INDEX_URL}" --extra-index-url "${TORCH_INDEX_URL}" --index-strategy unsafe-best-match \
  "${NBI_ARGS[@]}" \
  "${STAGE}" "${EXTRA_REQS[@]}"

# 6) 校验：CLI 存在、关键包可导入、torch 能看到 CUDA 13 GPU
[[ -x "${VENV}/bin/protenix" ]] || die "protenix console_script missing after install"
export PATH="${VENV}/bin:${CUDA_HOME}/bin:${PATH}"
export LAYERNORM_TYPE="${LAYERNORM_TYPE:-torch}"
echo "${TAG} LAYERNORM_TYPE=${LAYERNORM_TYPE}"
run_step verify_import "${VENV}/bin/python" -c '
import torch, protenix, runner.batch_inference, cuequivariance_torch, cuequivariance_ops_torch, biotite, rdkit, gemmi
assert torch.version.cuda and torch.version.cuda.startswith("13"), torch.version.cuda
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
x = torch.randn(1024, 1024, device="cuda"); y = (x @ x).sum().item()
print("torch", torch.__version__, "cuda", torch.version.cuda, "device", torch.cuda.get_device_name(0), "cap", torch.cuda.get_device_capability(0))
print("biotite", biotite.__version__, "rdkit", rdkit.__version__, "cuequivariance_ops_torch ok")
'
cat "${LOG_DIR}/install_verify_import.log"
run_step verify_cli "${VENV}/bin/protenix" --help
"${UV_BIN}" pip freeze --python "${VENV}/bin/python" > "${PREFIX}/conf/pip-freeze.txt"
echo "${TAG} freeze -> ${PREFIX}/conf/pip-freeze.txt"

# 7) 权重与 CCD 缓存：优先 WEIGHTS_REUSE_FROM 硬链接/拷贝校验，缺的再下载
fetch_one() {  # fetch_one <URL 表的键> <目标文件>
  local key="$1" dst="$2" url
  [[ -s "${dst}" ]] && { echo "${TAG} have ${dst}"; return 0; }
  url="$("${VENV}/bin/python" -c 'import sys; from protenix.web_service.dependency_url import URL; print(URL[sys.argv[1]])' "${key}")" \
    || die "no upstream URL for ${key}"
  mkdir -p "$(dirname "${dst}")"
  echo "${TAG} download ${key}: ${url}"
  curl -fL --retry 3 -o "${dst}.part" "${url}" || { rm -f "${dst}.part"; die "download failed: ${key} ${url}"; }
  mv "${dst}.part" "${dst}"
}
if [[ -n "${WEIGHTS_REUSE_FROM:-}" ]]; then
  REUSE_DATA="${WEIGHTS_REUSE_FROM}/protenix/data"
  [[ -d "${REUSE_DATA}" ]] || die "WEIGHTS_REUSE_FROM protenix data missing: ${REUSE_DATA}"
  echo "${TAG} reuse weights from ${REUSE_DATA}"
  seed_tree_verified "${REUSE_DATA}" "${DATA_ROOT}"
fi
if [[ "${PROTENIX_MODEL}" == protenix-v2* ]]; then
  [[ -s "${CKPT}" ]] || die "PROTENIX_MODEL=${PROTENIX_MODEL} 需要授权权重，本地缺少 ${CKPT}（官方地址 403，脚本不下载；请放入授权权重后重试，或改回 v1）"
  echo "${TAG} using licensed local weights ${CKPT}"
elif [[ "${SKIP_WEIGHTS:-0}" != "1" ]]; then
  fetch_one "${PROTENIX_MODEL}" "${CKPT}"
  for k in ccd_components_file:components.cif ccd_components_rdkit_mol_file:components.cif.rdkit_mol.pkl \
           pdb_cluster_file:clusters-by-entity-40.txt obsolete_release_data_csv:obsolete_release_date.csv; do
    fetch_one "${k%%:*}" "${DATA_ROOT}/common/${k#*:}"
  done
  if [[ "${PROTENIX_MODEL}" == *esm* || "${PROTENIX_MODEL}" == *ism* ]]; then
    echo "${TAG} NOTE: ${PROTENIX_MODEL} 还需要 ESM 权重，首次推理时由上游自动下载" >&2
  fi
fi
{
  echo "src_sha=${SRC_SHA}"
  echo "model=${PROTENIX_MODEL}"
  echo "python=${PYV}"
} > "${READY_MARK}"
echo "${TAG} status=ok src_sha=${SRC_SHA} model=${PROTENIX_MODEL}"
