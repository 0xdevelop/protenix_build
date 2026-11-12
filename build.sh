#!/bin/bash
# 只构建，不 bump 版本、不打 tag、不 push、不装系统服务。
# 用法：
#   ./build.sh [--help]
#   ./build.sh [all|protenix|pxdesign|go] [release|test|debug] [linux_amd64|linux_arm64|both|*.yaml]
# 默认 TARGET=all：Go 双 arch 打包 + prefix/protenix + prefix/pxdesign（两套独立 venv）。
# 幂等：已就绪步骤跳过（FORCE_*=1 强制重做）。
# PREFIX_ROOT：把双 prefix 装到 <PREFIX_ROOT>/{protenix,pxdesign}（默认 <repo>/prefix）。
# WEIGHTS_REUSE_FROM：从已校验 prefix 根硬链接/拷贝权重（见 scripts/weights_reuse.sh）。
set -euo pipefail

project_path=$(cd "$(dirname "$0")" && pwd)
cd "${project_path}"

TAG="[build]"
CANONICAL_PREFIX_ROOT="${project_path}/prefix"
PREFIX_ROOT="${PREFIX_ROOT:-${CANONICAL_PREFIX_ROOT}}"
PROTENIX_PREFIX="${PROTENIX_PREFIX:-${PREFIX_ROOT}/protenix}"
PXDESIGN_PREFIX="${PXDESIGN_PREFIX:-${PREFIX_ROOT}/pxdesign}"
export PREFIX_ROOT PROTENIX_PREFIX PXDESIGN_PREFIX
# WEIGHTS_REUSE_FROM 透传给 install_prefix_*.sh（可空）
if [[ -n "${WEIGHTS_REUSE_FROM:-}" ]]; then
  export WEIGHTS_REUSE_FROM
fi

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--help]
  ./build.sh [all|protenix|pxdesign|go] [release|test|debug] [linux_amd64|linux_arm64|both|*.yaml]

Targets (default: all):
  all       Go 双 arch 打包 + prefix/protenix + prefix/pxdesign
  go        只构建/打包 Go supervisor（protenixd / pxdesignd）与 zip
  protenix  只安装/校验 prefix/protenix（uv + Python 3.14 + torch cu130）
  pxdesign  只安装/校验 prefix/pxdesign（独立 venv；复用 scripts/install_prefix_pxdesign.sh）

Idempotency:
  已就绪则跳过。强制重装：FORCE_PROTENIX=1 / FORCE_PXDESIGN=1 / FORCE_GO=1
  或 RECREATE_VENV=1 传给 protenix 安装脚本。

Prefix:
  PREFIX_ROOT=<dir>     安装到 <dir>/{protenix,pxdesign}（默认 <repo>/prefix）
  WEIGHTS_REUSE_FROM=<已校验 prefix 根>  硬链接/拷贝权重并校 size/sha256

Notes:
  - 不做发布（发版走 git_tag.sh / Actions）
  - 不合并两个 prefix venv；不用 Docker / conda / Python 3.11
  - 版本号来自 gen_pre_build_config_*.yaml（由 gen_pre_build_config.sh 生成）
  - BUILD_INFO：工作区相对 HEAD dirty 时 commit 带 -dirty 后缀，并写 dirty=1
  - 交付 zip 前应先提交再 FORCE_GO=1 打包，使 BUILD_INFO.commit == HEAD
EOF
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "${HOME}/.local/go/bin/go" ]]; then
    export PATH="${HOME}/.local/go/bin:${PATH}"
    return 0
  fi
  echo "${TAG} go not found in PATH (expected host Go or ~/.local/go/bin/go)" >&2
  exit 1
}

ensure_zip() {
  if ! command -v zip >/dev/null 2>&1; then
    echo "${TAG} zip not found in PATH" >&2
    exit 1
  fi
}

# --- arg parse ---
TARGET="all"
RUN_MODE_ARG="release"
ARCH_ARGS=()

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  case "$1" in
    all|protenix|pxdesign|go)
      TARGET="$1"
      shift
      ;;
    release|test|debug)
      # 兼容旧用法：./build.sh release linux_arm64 → 等同 go
      TARGET="go"
      RUN_MODE_ARG="$1"
      shift
      ;;
    linux_amd64|linux_arm64|both|*.yaml|*.yml)
      TARGET="go"
      ;;
    *)
      echo "${TAG} unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    release|test|debug)
      RUN_MODE_ARG="$1"
      ;;
    linux_amd64|linux_arm64|both|*.yaml|*.yml)
      ARCH_ARGS+=("$1")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "${TAG} unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "${RUN_MODE_ARG}" in
  release|test|debug) ;;
  *)
    echo "${TAG} invalid run mode: ${RUN_MODE_ARG}" >&2
    exit 2
    ;;
esac

ensure_go
mkdir -p tmp

resolve_config() {
  local arg="$1"
  case "${arg}" in
    linux_amd64) echo "gen_pre_build_config_linux_amd64.yaml" ;;
    linux_arm64) echo "gen_pre_build_config_linux_arm64.yaml" ;;
    both)
      echo "both"
      ;;
    *.yaml|*.yml)
      [[ -f "${arg}" ]] || { echo "${TAG} config not found: ${arg}" >&2; exit 1; }
      echo "${arg}"
      ;;
    *)
      echo "${TAG} unknown config selector: ${arg}" >&2
      exit 1
      ;;
  esac
}

host_arch_selector() {
  local host_arch
  host_arch="$(uname -m)"
  case "${host_arch}" in
    x86_64|amd64) echo "linux_amd64" ;;
    aarch64|arm64) echo "linux_arm64" ;;
    *)
      echo "${TAG} cannot infer arch from ${host_arch}" >&2
      exit 1
      ;;
  esac
}

# 解析要打包的 gen yaml 列表（go / all 用）
GO_CONFIGS=()
if [[ ${#ARCH_ARGS[@]} -eq 0 ]]; then
  if [[ "${TARGET}" == "go" || "${TARGET}" == "all" ]]; then
    # 默认双 arch
    GO_CONFIGS=("gen_pre_build_config_linux_amd64.yaml" "gen_pre_build_config_linux_arm64.yaml")
  fi
else
  for a in "${ARCH_ARGS[@]}"; do
    resolved="$(resolve_config "${a}")"
    if [[ "${resolved}" == "both" ]]; then
      GO_CONFIGS+=("gen_pre_build_config_linux_amd64.yaml" "gen_pre_build_config_linux_arm64.yaml")
    else
      GO_CONFIGS+=("${resolved}")
    fi
  done
fi

# 去重保序
if [[ ${#GO_CONFIGS[@]} -gt 0 ]]; then
  _dedup=()
  for c in "${GO_CONFIGS[@]}"; do
    _seen=0
    for d in "${_dedup[@]:-}"; do
      [[ "${d}" == "${c}" ]] && _seen=1 && break
    done
    [[ ${_seen} -eq 0 ]] && _dedup+=("${c}")
  done
  GO_CONFIGS=("${_dedup[@]}")
fi

load_export() {
  local config_file="$1"
  [[ -f "${config_file}" ]] || { echo "${TAG} missing ${config_file}; run ./gen_pre_build_config.sh all first" >&2; exit 1; }
  local export_file="tmp/build_export_${config_file##*/}.env"
  # yaml 导出也含 PREFIX_ROOT，不能冲掉用户指定的安装根
  local _keep_prefix_root="${PREFIX_ROOT}"
  local _keep_protenix_prefix="${PROTENIX_PREFIX}"
  local _keep_pxdesign_prefix="${PXDESIGN_PREFIX}"
  local _keep_weights_reuse="${WEIGHTS_REUSE_FROM:-}"
  go run gen_pre_build_config.go -validate "${config_file}"
  go run gen_pre_build_config.go -export "${config_file}" > "${export_file}"
  # shellcheck disable=SC1090
  source "${export_file}"
  PREFIX_ROOT="${_keep_prefix_root}"
  PROTENIX_PREFIX="${_keep_protenix_prefix}"
  PXDESIGN_PREFIX="${_keep_pxdesign_prefix}"
  export PREFIX_ROOT PROTENIX_PREFIX PXDESIGN_PREFIX
  if [[ -n "${_keep_weights_reuse}" ]]; then
    WEIGHTS_REUSE_FROM="${_keep_weights_reuse}"
    export WEIGHTS_REUSE_FROM
  fi
}

pack_one_product() {
  local name="$1"
  local prefix
  prefix="$(echo "${name}" | tr 'a-z-' 'A-Z_')"

  local src_var="PRODUCT_${prefix}_SRC"
  local sub_var="PRODUCT_${prefix}_BUILD_SUBDIR"
  local svc_var="PRODUCT_${prefix}_SERVICE"
  local oneshot_var="PRODUCT_${prefix}_ONESHOT"
  local env_var="PRODUCT_${prefix}_ENV"
  local wrap_var="PRODUCT_${prefix}_WRAPPER"
  local inst_var="PRODUCT_${prefix}_INSTALL"
  local pinst_var="PRODUCT_${prefix}_PREFIX_INSTALL"
  local policy_var="PRODUCT_${prefix}_ENV_POLICY"
  local cli_var="PRODUCT_${prefix}_CLI"
  local wrapname_var="PRODUCT_${prefix}_WRAPPER_NAME"
  local superv_var="PRODUCT_${prefix}_SUPERVISOR_BIN"
  local superv_cmd_var="PRODUCT_${prefix}_SUPERVISOR_CMD_PATH"
  local pinned_var="PRODUCT_${prefix}_PINNED_PROTENIX_REF"
  local torch_var="PRODUCT_${prefix}_TORCH_HINT"

  local src="${!src_var}"
  local subdir="${!sub_var}"
  local service="${!svc_var}"
  local oneshot="${!oneshot_var}"
  local envf="${!env_var}"
  local wrapper="${!wrap_var}"
  local install_sh="${!inst_var}"
  local prefix_install="${!pinst_var}"
  local policy="${!policy_var}"
  local cli="${!cli_var}"
  local wrapname="${!wrapname_var}"
  local superv_bin="${!superv_var}"
  local superv_cmd="${!superv_cmd_var}"
  local pinned_ref="${!pinned_var}"
  local torch_hint="${!torch_var}"

  local out_dir="${BUILD_MODE_ROOT}/${subdir}"
  rm -rf "${out_dir}"
  mkdir -p "${out_dir}/bin" "${out_dir}/conf" "${out_dir}/systemd" "${out_dir}/scripts" "${out_dir}/docs" \
    "${out_dir}/constraints" "${out_dir}/src/${name}"

  [[ -d "${superv_cmd}" ]] || { echo "${TAG} missing supervisor cmd path ${superv_cmd}" >&2; exit 1; }
  [[ -d "${src}" ]] || { echo "${TAG} missing upstream src ${src}" >&2; exit 1; }
  git -C "${src}" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { echo "${TAG} upstream src is not a git work tree: ${src}" >&2; exit 1; }
  local src_sha
  src_sha="$(git -C "${src}" rev-parse HEAD)"
  echo "${TAG} go build ${superv_bin} for ${GOOS_TARGET}/${GOARCH_TARGET}"
  CGO_ENABLED=0 GOOS="${GOOS_TARGET}" GOARCH="${GOARCH_TARGET}" \
    go build -trimpath -ldflags "-s -w" -o "${out_dir}/bin/${superv_bin}" "./${superv_cmd}"
  chmod a+x "${out_dir}/bin/${superv_bin}"

  echo "${TAG} bundle upstream ${name} @ ${src_sha:0:12} via git archive"
  git -C "${src}" archive --format=tar HEAD | tar -x -C "${out_dir}/src/${name}"
  printf '%s\n' "${src_sha}" > "${out_dir}/src/SRC_SHA"
  [[ -f "${out_dir}/src/${name}/setup.py" ]] || { echo "${TAG} git archive missing setup.py for ${name}" >&2; exit 1; }

  case "${name}" in
    protenix)
      cp -f "${project_path}/constraints/py314-cu130.txt" "${out_dir}/constraints/"
      ;;
    pxdesign)
      cp -f "${project_path}/constraints/pxdesign-py314-cu130.txt" "${out_dir}/constraints/"
      cp -f "${project_path}/constraints/pxdesign-py314-argparse-percent.patch" "${out_dir}/constraints/"
      cp -f "${project_path}/constraints/pxdbench-af2-json-float32.patch" "${out_dir}/constraints/"
      ;;
    *)
      echo "${TAG} unknown product for constraints bundle: ${name}" >&2
      exit 1
      ;;
  esac

  cat > "${out_dir}/BUILD_INFO.txt" <<EOF
product=${name}
project=${PROJECT_NAME}
version=${PROJECT_VERSION}
run_mode=${RUN_MODE}
goos=${GOOS_TARGET}
goarch=${GOARCH_TARGET}
install_prefix=${INSTALL_PREFIX}
src_path=src/${name}
src_sha=${src_sha}
env_policy=${policy}
pinned_protenix_ref=${pinned_ref}
torch_hint=${torch_hint}
cli_name=${cli}
wrapper_name=${wrapname}
supervisor_bin=${superv_bin}
systemd_smoke=oneshot
systemd_batch=oneshot
commit=${commit_for_info}
commit_head=${commit_hash}
dirty=${commit_dirty}
build_time=${build_time}
note=self-contained zip: src/ + constraints/ + scripts/; pip/weights still need network
EOF

  for f in "${service}" "${oneshot}" "${envf}" "${wrapper}" "${install_sh}" "${prefix_install}"; do
    [[ -f "${f}" ]] || { echo "${TAG} missing ${f}" >&2; exit 1; }
  done

  cp -f "${service}" "${out_dir}/systemd/$(basename "${service}")"
  cp -f "${oneshot}" "${out_dir}/systemd/$(basename "${oneshot}")"
  cp -f "${envf}" "${out_dir}/conf/$(basename "${envf}")"
  cp -f "${wrapper}" "${out_dir}/bin/$(basename "${wrapper}")"
  chmod a+x "${out_dir}/bin/$(basename "${wrapper}")"
  cp -f "${install_sh}" "${out_dir}/install_${name}.sh"
  chmod a+x "${out_dir}/install_${name}.sh"
  cp -f "${prefix_install}" "${out_dir}/scripts/$(basename "${prefix_install}")"
  chmod a+x "${out_dir}/scripts/$(basename "${prefix_install}")"
  cp -f "${project_path}/scripts/weights_reuse.sh" "${out_dir}/scripts/weights_reuse.sh"
  chmod a+x "${out_dir}/scripts/weights_reuse.sh"
  # 不打包 scripts/repo_src_defaults.sh：包内只走 src/ 快照

  if [[ -d "${src}/examples" ]]; then
    mkdir -p "${out_dir}/examples_ref"
    find "${src}/examples" -maxdepth 2 \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.cif' \) -type f 2>/dev/null | head -40 | while read -r f; do
      rel="${f#${src}/examples/}"
      mkdir -p "${out_dir}/examples_ref/$(dirname "${rel}")"
      cp -f "${f}" "${out_dir}/examples_ref/${rel}"
    done || true
  fi

  local install_prefix_env
  install_prefix_env="$(echo "${name}" | tr 'a-z' 'A-Z')_INSTALL_PREFIX"
  if [[ "${name}" == "protenix" ]]; then
    cat > "${out_dir}/docs/README_RUN.md" <<EOF
# Protenix 使用说明

## 前置

- NVIDIA GB10 / 对应 arch；CUDA 13 驱动与 \`nvcc\`（默认 \`CUDA_HOME=/usr/local/cuda-13.0\`）
- 已装 uv，可解析 Python 3.14；无需 sudo / Docker / conda

## 安装

\`\`\`bash
cd /path/to/protenix   # 本 zip 解压根目录
PREFIX_ROOT=/opt/protenix_prefix \\
WEIGHTS_REUSE_FROM=/path/to/existing_prefix_root \\
  bash scripts/install_prefix_protenix.sh
${install_prefix_env}=\$PREFIX_ROOT/protenix bash install_protenix.sh
\`\`\`

公开权重可自动下载；\`PROTENIX_MODEL=protenix-v2\` 需自备授权权重。包内已含 \`src/protenix/\`（见 \`src/SRC_SHA\`）与 \`constraints/\`。

## 跑一次预测

\`\`\`bash
export PATH="\$PREFIX_ROOT/protenix/venv/bin:\$PATH" LAYERNORM_TYPE=torch SUPERVISOR_PREFIX="\$PREFIX_ROOT/protenix"
"\$PREFIX_ROOT/protenix/bin/protenixd" pred \\
  -i examples_ref/input.json -o "\$PREFIX_ROOT/protenix/jobs/out" \\
  -n protenix_base_default_v1.0.0 --use_msa false -s 101
\`\`\`

验收：rc=0、输出有 \`.cif\`、无 \`ERR/\`、GPU 利用率 > 0。

## systemd

- 用户级（无 sudo）：\`INSTALL_SYSTEMD=1 SYSTEMD_PATH=\$HOME/.config/systemd/user bash install_protenix.sh && systemctl --user daemon-reload\`
- 系统级（需 root）：\`INSTALL_SYSTEMD=1 SYSTEMD_PATH=/etc/systemd/system bash install_protenix.sh\`
- 冒烟 unit：\`protenix.service\`（oneshot）；批作业：\`protenix-oneshot.service\`
EOF
  else
    cat > "${out_dir}/docs/README_RUN.md" <<EOF
# PXDesign 使用说明

## 前置

- NVIDIA GB10 / 对应 arch；CUDA 13 驱动与 \`nvcc\`（默认 \`CUDA_HOME=/usr/local/cuda-13.0\`）
- 已装 uv，可解析 Python 3.14；无需 sudo / Docker / conda

## 安装

\`\`\`bash
cd /path/to/pxdesign
PREFIX_ROOT=/opt/pxdesign_prefix \\
WEIGHTS_REUSE_FROM=/path/to/existing_prefix_root \\
  bash scripts/install_prefix_pxdesign.sh
${install_prefix_env}=\$PREFIX_ROOT/pxdesign bash install_pxdesign.sh
\`\`\`

包内已含 \`src/pxdesign/\`（见 \`src/SRC_SHA\`）、\`constraints/\` 与运行期补丁。

## 跑一次设计

\`\`\`bash
export PATH="\$PREFIX_ROOT/pxdesign/venv/bin:\$PATH" LAYERNORM_TYPE=torch
export TOOL_WEIGHTS_ROOT="\$PREFIX_ROOT/pxdesign/tool_weights"
export PROTENIX_DATA_ROOT_DIR="\$PREFIX_ROOT/pxdesign/protenix_data"
mkdir -p /tmp/pxd_job && cp -a examples_ref /tmp/pxd_job/examples
( cd /tmp/pxd_job && pxdesign pipeline --preset preview \\
  -i ./examples/PDL1_quick_start.yaml -o ./out \\
  --N_sample 2 --num_workers 0 --use_fast_ln False \\
  --load_checkpoint_dir "\$PREFIX_ROOT/pxdesign/release_data/checkpoint" )
\`\`\`

验收：rc=0、输出有 \`.cif\`、无 \`ERR/\`、GPU 利用率 > 0。

## systemd

- 用户级（无 sudo）：\`INSTALL_SYSTEMD=1 SYSTEMD_PATH=\$HOME/.config/systemd/user bash install_pxdesign.sh && systemctl --user daemon-reload\`
- 系统级（需 root）：\`INSTALL_SYSTEMD=1 SYSTEMD_PATH=/etc/systemd/system bash install_pxdesign.sh\`
- 冒烟 unit：\`pxdesign.service\`（oneshot）；批作业：\`pxdesign-oneshot.service\`
EOF
  fi

  local zip_name="${name}_${GOOS_TARGET}_${GOARCH_TARGET}_${RUN_MODE}_${PROJECT_VERSION}.zip"
  local zip_path="${project_path}/${UPLOAD_TMP_DIR}/${zip_name}"
  rm -f "${zip_path}"
  ( cd "${BUILD_MODE_ROOT}" && zip -r "${zip_path}" "${subdir}" >/dev/null )
  echo "${TAG} packed ${UPLOAD_TMP_DIR}/${zip_name} (src_sha=${src_sha:0:12})"
}

go_artifact_ready() {
  # 依赖已 load_export；用 stamp + bin + zip 判定是否可跳过。
  # dirty 工作区不跳过，避免把过期/未提交改动的包当成交付物。
  local mode="$1"
  local stamp="build/${mode}/.go_ready_${GOOS_TARGET}_${GOARCH_TARGET}"
  local expect="${PROJECT_VERSION}|${commit_hash}|dirty=${commit_dirty}|${GOOS_TARGET}|${GOARCH_TARGET}"
  [[ "${FORCE_GO:-0}" == "1" ]] && return 1
  [[ "${commit_dirty}" == "1" ]] && return 1
  [[ -f "${stamp}" ]] || return 1
  [[ "$(cat "${stamp}")" == "${expect}" ]] || return 1
  for product in ${PRODUCT_NAMES}; do
    local prefix sub_var superv_var
    prefix="$(echo "${product}" | tr 'a-z-' 'A-Z_')"
    sub_var="PRODUCT_${prefix}_BUILD_SUBDIR"
    superv_var="PRODUCT_${prefix}_SUPERVISOR_BIN"
    local subdir="${!sub_var}"
    local superv_bin="${!superv_var}"
    [[ -x "build/${mode}/${subdir}/bin/${superv_bin}" ]] || return 1
    local zip_path="${UPLOAD_TMP_DIR}/${product}_${GOOS_TARGET}_${GOARCH_TARGET}_${mode}_${PROJECT_VERSION}.zip"
    [[ -s "${zip_path}" ]] || return 1
    # zip 内 BUILD_INFO 必须等于当前 HEAD 且 dirty=0
    local bi
    bi="$(unzip -p "${zip_path}" "${subdir}/BUILD_INFO.txt" 2>/dev/null || true)"
    echo "${bi}" | grep -qx "commit=${commit_hash}" || return 1
    echo "${bi}" | grep -qx "dirty=0" || return 1
  done
  return 0
}

build_go_one() {
  local config_file="$1"
  load_export "${config_file}"
  local RUN_MODE="${RUN_MODE_ARG}"
  local BUILD_MODE_ROOT="${BUILD_ROOT}/${RUN_MODE}"
  mkdir -p "${BUILD_MODE_ROOT}" "${UPLOAD_TMP_DIR}"

  if go_artifact_ready "${RUN_MODE}"; then
    echo "${TAG} skip go ${GOOS_TARGET}/${GOARCH_TARGET} (ready: ${PROJECT_VERSION} @ ${commit_hash:0:12} dirty=0)"
    return 0
  fi

  echo "${TAG} project=${PROJECT_NAME} version=${PROJECT_VERSION} mode=${RUN_MODE} target=${GOOS_TARGET}/${GOARCH_TARGET}"
  echo "${TAG} commit=${commit_for_info} commit_date=${commit_date} build_time=${build_time}"

  for product in ${PRODUCT_NAMES}; do
    pack_one_product "${product}"
  done

  local stamp="build/${RUN_MODE}/.go_ready_${GOOS_TARGET}_${GOARCH_TARGET}"
  if [[ "${commit_dirty}" == "0" ]]; then
    echo "${PROJECT_VERSION}|${commit_hash}|dirty=0|${GOOS_TARGET}|${GOARCH_TARGET}" > "${stamp}"
  else
    rm -f "${stamp}"
    echo "${TAG} WARN: working tree dirty → BUILD_INFO.commit=${commit_for_info}；交付前请先 commit 再 FORCE_GO=1 重打包" >&2
  fi
  echo "${TAG} go done ${GOOS_TARGET}/${GOARCH_TARGET}"
}

build_go() {
  ensure_zip
  [[ ${#GO_CONFIGS[@]} -gt 0 ]] || GO_CONFIGS=("gen_pre_build_config_linux_amd64.yaml" "gen_pre_build_config_linux_arm64.yaml")
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  commit_date="$(git show -s --format='%ci' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S %z')"
  build_time="$(date +'%Y-%m-%d_%H:%M:%S')"
  if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    commit_dirty=1
    commit_for_info="${commit_hash}-dirty"
  else
    commit_dirty=0
    commit_for_info="${commit_hash}"
  fi
  for cfg in "${GO_CONFIGS[@]}"; do
    build_go_one "${cfg}"
  done
  echo "${TAG} go zips:"
  ls -la build/upload_tmp_dir/*_"${RUN_MODE_ARG}"_*.zip 2>/dev/null || ls -la build/upload_tmp_dir/*.zip
}

protenix_prefix_ready() {
  local p="${PROTENIX_PREFIX}"
  local venv="${p}/venv"
  [[ "${FORCE_PROTENIX:-0}" == "1" ]] && return 1
  [[ "${RECREATE_VENV:-0}" == "1" ]] && return 1
  [[ -x "${venv}/bin/protenix" ]] || return 1
  [[ -x "${venv}/bin/python" ]] || return 1
  local pyv
  pyv="$("${venv}/bin/python" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
  [[ "${pyv}" == 3.14.* ]] || return 1
  local model="protenix_base_default_v1.0.0"
  if [[ -f "${p}/conf/protenix.env" ]]; then
    local m
    m="$(sed -n 's/^PROTENIX_MODEL=//p' "${p}/conf/protenix.env" | tail -n1 | tr -d '"')"
    [[ -n "${m}" ]] && model="${m}"
  fi
  model="${PROTENIX_MODEL:-${model}}"
  local data_root="${p}/data"
  if [[ -f "${p}/conf/protenix.env" ]]; then
    local d
    d="$(sed -n 's/^PROTENIX_ROOT_DIR=//p' "${p}/conf/protenix.env" | tail -n1 | tr -d '"')"
    [[ -n "${d}" ]] && data_root="${d}"
  fi
  [[ -s "${data_root}/checkpoint/${model}.pt" ]] || return 1
  [[ -f "${p}/conf/pip-freeze.txt" ]] || return 1
  return 0
}

build_protenix() {
  echo "${TAG} PREFIX_ROOT=${PREFIX_ROOT} PROTENIX_PREFIX=${PROTENIX_PREFIX}"
  if protenix_prefix_ready; then
    echo "${TAG} skip protenix prefix (venv+CLI+weights ready at ${PROTENIX_PREFIX})"
    return 0
  fi
  echo "${TAG} install ${PROTENIX_PREFIX}"
  bash "${project_path}/scripts/install_prefix_protenix.sh"
  protenix_prefix_ready || { echo "${TAG} FAIL: protenix prefix not ready after install" >&2; exit 1; }
}

pxdesign_prefix_ready() {
  local p="${PXDESIGN_PREFIX}"
  local venv="${p}/venv"
  [[ "${FORCE_PXDESIGN:-0}" == "1" ]] && return 1
  [[ -x "${venv}/bin/pxdesign" ]] || return 1
  [[ -x "${venv}/bin/python" ]] || return 1
  local pyv
  pyv="$("${venv}/bin/python" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
  [[ "${pyv}" == 3.14.* ]] || return 1
  [[ -f "${p}/conf/pip-freeze.txt" ]] || return 1
  [[ -s "${p}/release_data/checkpoint/pxdesign_v0.1.0.pt" ]] || return 1
  [[ -s "${p}/tool_weights/af2/params_model_1.npz" ]] || return 1
  return 0
}

build_pxdesign() {
  echo "${TAG} PREFIX_ROOT=${PREFIX_ROOT} PXDESIGN_PREFIX=${PXDESIGN_PREFIX}"
  if pxdesign_prefix_ready; then
    echo "${TAG} skip pxdesign prefix (independent venv+CLI+weights ready at ${PXDESIGN_PREFIX})"
    return 0
  fi
  echo "${TAG} install ${PXDESIGN_PREFIX} (independent venv; not merged with protenix)"
  bash "${project_path}/scripts/install_prefix_pxdesign.sh"
  pxdesign_prefix_ready || { echo "${TAG} FAIL: pxdesign prefix not ready after install" >&2; exit 1; }
}

echo "${TAG} target=${TARGET} mode=${RUN_MODE_ARG} PREFIX_ROOT=${PREFIX_ROOT}"
case "${TARGET}" in
  go)
    build_go
    ;;
  protenix)
    build_protenix
    ;;
  pxdesign)
    build_pxdesign
    ;;
  all)
    build_go
    build_protenix
    build_pxdesign
    ;;
  *)
    echo "${TAG} unknown target: ${TARGET}" >&2
    exit 2
    ;;
esac

echo "${TAG} done target=${TARGET}"
