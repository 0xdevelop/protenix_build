#!/bin/bash
# 只构建，不 bump 版本、不打 tag、不 push、不装系统服务。
# 用法：
#   ./build.sh [--help]
#   ./build.sh [all|pack|protenix|pxdesign] [release|test|debug] [linux_amd64|linux_arm64|both|*.yaml]
# 默认 TARGET=all：双 arch 发布包 + prefix/protenix + prefix/pxdesign（两套独立 venv）。
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
  ./build.sh [all|pack|protenix|pxdesign] [release|test|debug] [linux_amd64|linux_arm64|both|*.yaml]

Targets (default: all):
  all       双 arch 发布包 + prefix/protenix + prefix/pxdesign
  pack      只打发布包 build/upload_tmp_dir/<app>_linux_<arch>_<mode>_<version>.zip
  protenix  只安装/校验 prefix/protenix（uv + Python 3.14 + torch cu130）
  pxdesign  只安装/校验 prefix/pxdesign（独立 venv；复用 scripts/install_prefix_pxdesign.sh）

Idempotency:
  已就绪则跳过。强制重做：FORCE_PROTENIX=1 / FORCE_PXDESIGN=1 / FORCE_PACK=1
  或 RECREATE_VENV=1 传给 protenix 安装脚本。

Prefix:
  PREFIX_ROOT=<dir>     安装到 <dir>/{protenix,pxdesign}（默认 <repo>/prefix）
  WEIGHTS_REUSE_FROM=<已校验 prefix 根>  硬链接/拷贝权重并校 size/sha256

Notes:
  - 不做发布（发版走 git_tag.sh / Actions）
  - 不合并两个 prefix venv；不用 Docker / conda / Python 3.11
  - 版本号来自 gen_pre_build_config_*.yaml（由 gen_pre_build_config.sh 生成）
  - BUILD_INFO：工作区相对 HEAD dirty 时 commit 带 -dirty 后缀，并写 dirty=1
  - 交付 zip 前应先提交再 FORCE_PACK=1 打包，使 BUILD_INFO.commit == HEAD
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
    all|pack|protenix|pxdesign)
      TARGET="$1"
      shift
      ;;
    release|test|debug)
      # ./build.sh release linux_arm64（release.yml 用法）→ 等同 pack
      TARGET="pack"
      RUN_MODE_ARG="$1"
      shift
      ;;
    linux_amd64|linux_arm64|both|*.yaml|*.yml)
      TARGET="pack"
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

# 解析要打包的 gen yaml 列表（pack / all 用）
GO_CONFIGS=()
if [[ ${#ARCH_ARGS[@]} -eq 0 ]]; then
  if [[ "${TARGET}" == "pack" || "${TARGET}" == "all" ]]; then
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
  local up
  up="$(echo "${name}" | tr 'a-z-' 'A-Z_')"
  local src_var="PRODUCT_${up}_SRC" sub_var="PRODUCT_${up}_BUILD_SUBDIR" env_var="PRODUCT_${up}_ENV"
  local wrap_var="PRODUCT_${up}_WRAPPER" inst_var="PRODUCT_${up}_INSTALL" pinst_var="PRODUCT_${up}_PREFIX_INSTALL"
  local policy_var="PRODUCT_${up}_ENV_POLICY" pinned_var="PRODUCT_${up}_PINNED_PROTENIX_REF" torch_var="PRODUCT_${up}_TORCH_HINT"
  local src="${!src_var}" subdir="${!sub_var}" envf="${!env_var}" wrapper="${!wrap_var}"
  local install_sh="${!inst_var}" prefix_install="${!pinst_var}"
  local policy="${!policy_var}" pinned_ref="${!pinned_var}" torch_hint="${!torch_var}"

  local out_dir="${BUILD_MODE_ROOT}/${subdir}"
  rm -rf "${out_dir}"
  mkdir -p "${out_dir}/bin" "${out_dir}/conf" "${out_dir}/scripts" "${out_dir}/deps" "${out_dir}/patches" "${out_dir}/src/${name}"

  [[ -d "${src}" ]] || { echo "${TAG} missing upstream src ${src}" >&2; exit 1; }
  git -C "${src}" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { echo "${TAG} upstream src is not a git work tree: ${src}" >&2; exit 1; }
  local src_sha
  src_sha="$(git -C "${src}" rev-parse HEAD)"
  echo "${TAG} bundle upstream ${name} @ ${src_sha:0:12} via git archive"
  git -C "${src}" archive --format=tar HEAD | tar -x -C "${out_dir}/src/${name}"
  printf '%s\n' "${src_sha}" > "${out_dir}/src/SRC_SHA"
  [[ -f "${out_dir}/src/${name}/setup.py" ]] || { echo "${TAG} git archive missing setup.py for ${name}" >&2; exit 1; }

  cp -f "${project_path}/deps/${name}.txt" "${out_dir}/deps/"
  if [[ "${name}" == "pxdesign" ]]; then
    cp -f "${project_path}/patches/pxdesign-argparse-percent.patch" "${project_path}/patches/pxdbench-json-float.patch" \
      "${out_dir}/patches/"
  fi

  local readme="${project_path}/docs/package_${name}.md"
  for f in "${envf}" "${wrapper}" "${install_sh}" "${prefix_install}" "${readme}" \
           "${project_path}/scripts/install_common.sh" "${project_path}/scripts/weights_reuse.sh"; do
    [[ -f "${f}" ]] || { echo "${TAG} missing ${f}" >&2; exit 1; }
  done
  cp -f "${install_sh}" "${out_dir}/install_${name}.sh"
  cp -f "${wrapper}" "${out_dir}/bin/${name}-run"
  cp -f "${envf}" "${out_dir}/conf/${name}.env"
  cp -f "${prefix_install}" "${project_path}/scripts/install_common.sh" "${project_path}/scripts/weights_reuse.sh" \
    "${out_dir}/scripts/"
  cp -f "${readme}" "${out_dir}/README.md"
  chmod a+x "${out_dir}/install_${name}.sh" "${out_dir}/bin/${name}-run" "${out_dir}/scripts/"*.sh
  if [[ -d "${src}/examples" ]]; then
    cp -a "${src}/examples" "${out_dir}/examples"
  fi

  cat > "${out_dir}/BUILD_INFO.txt" <<PBINFO
product=${name}
project=${PROJECT_NAME}
version=${PROJECT_VERSION}
run_mode=${RUN_MODE}
goos=${GOOS_TARGET}
goarch=${GOARCH_TARGET}
src_sha=${src_sha}
env_policy=${policy}
pinned_protenix_ref=${pinned_ref}
torch_hint=${torch_hint}
commit=${commit_for_info}
commit_head=${commit_hash}
dirty=${commit_dirty}
build_time=${build_time}
PBINFO

  local zip_name="${name}_${GOOS_TARGET}_${GOARCH_TARGET}_${RUN_MODE}_${PROJECT_VERSION}.zip"
  local zip_path="${project_path}/${UPLOAD_TMP_DIR}/${zip_name}"
  rm -f "${zip_path}"
  ( cd "${BUILD_MODE_ROOT}" && zip -qr "${zip_path}" "${subdir}" )
  echo "${TAG} packed ${UPLOAD_TMP_DIR}/${zip_name} (src_sha=${src_sha:0:12})"
}

pack_ready() {
  local mode="$1"
  [[ "${FORCE_PACK:-0}" == "1" ]] && return 1
  [[ "${commit_dirty}" == "1" ]] && return 1
  for product in ${PRODUCT_NAMES}; do
    local up sub_var subdir bi
    up="$(echo "${product}" | tr 'a-z-' 'A-Z_')"
    sub_var="PRODUCT_${up}_BUILD_SUBDIR"
    subdir="${!sub_var}"
    local zip_path="${UPLOAD_TMP_DIR}/${product}_${GOOS_TARGET}_${GOARCH_TARGET}_${mode}_${PROJECT_VERSION}.zip"
    [[ -s "${zip_path}" ]] || return 1
    bi="$(unzip -p "${zip_path}" "${subdir}/BUILD_INFO.txt" 2>/dev/null || true)"
    echo "${bi}" | grep -qx "commit=${commit_hash}" || return 1
    echo "${bi}" | grep -qx "dirty=0" || return 1
    unzip -l "${zip_path}" "${subdir}/install_${product}.sh" >/dev/null 2>&1 || return 1
    unzip -l "${zip_path}" "${subdir}/src/${product}/setup.py" >/dev/null 2>&1 || return 1
  done
  return 0
}

build_pack_one() {
  local config_file="$1"
  load_export "${config_file}"
  local RUN_MODE="${RUN_MODE_ARG}"
  local BUILD_MODE_ROOT="${BUILD_ROOT}/${RUN_MODE}"
  mkdir -p "${BUILD_MODE_ROOT}" "${UPLOAD_TMP_DIR}"
  if pack_ready "${RUN_MODE}"; then
    echo "${TAG} skip pack ${GOOS_TARGET}/${GOARCH_TARGET} (ready: ${PROJECT_VERSION} @ ${commit_hash:0:12} dirty=0)"
    return 0
  fi
  echo "${TAG} project=${PROJECT_NAME} version=${PROJECT_VERSION} mode=${RUN_MODE} target=${GOOS_TARGET}/${GOARCH_TARGET}"
  echo "${TAG} commit=${commit_for_info} build_time=${build_time}"
  for product in ${PRODUCT_NAMES}; do
    pack_one_product "${product}"
  done
  if [[ "${commit_dirty}" == "1" ]]; then
    echo "${TAG} WARN: working tree dirty -> BUILD_INFO.commit=${commit_for_info}; commit then FORCE_PACK=1" >&2
  fi
}

build_pack() {
  ensure_zip
  [[ ${#GO_CONFIGS[@]} -gt 0 ]] || GO_CONFIGS=("gen_pre_build_config_linux_amd64.yaml" "gen_pre_build_config_linux_arm64.yaml")
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  build_time="$(date +'%Y-%m-%d_%H:%M:%S')"
  if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    commit_dirty=1
    commit_for_info="${commit_hash}-dirty"
  else
    commit_dirty=0
    commit_for_info="${commit_hash}"
  fi
  for cfg in "${GO_CONFIGS[@]}"; do
    build_pack_one "${cfg}"
  done
  ls -la build/upload_tmp_dir/*_"${RUN_MODE_ARG}"_*.zip
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
  local src="${project_path}/build_srcs/protenix"
  [[ -d "${src}" ]] || { echo "${TAG} missing ${src}; run git submodule update --init --recursive" >&2; exit 1; }
  echo "${TAG} install ${PROTENIX_PREFIX}"
  PROTENIX_SRC="${src}" \
    SRC_SHA="$(git -C "${src}" rev-parse HEAD)" \
    PROTENIX_OVERRIDES="${project_path}/deps/protenix.txt" \
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
  local src="${project_path}/build_srcs/pxdesign"
  [[ -d "${src}" ]] || { echo "${TAG} missing ${src}; run git submodule update --init --recursive" >&2; exit 1; }
  echo "${TAG} install ${PXDESIGN_PREFIX} (independent venv; not merged with protenix)"
  PXDESIGN_SRC="${src}" \
    SRC_SHA="$(git -C "${src}" rev-parse HEAD)" \
    PXDESIGN_OVERRIDES="${project_path}/deps/pxdesign.txt" \
    bash "${project_path}/scripts/install_prefix_pxdesign.sh"
  pxdesign_prefix_ready || { echo "${TAG} FAIL: pxdesign prefix not ready after install" >&2; exit 1; }
}

echo "${TAG} target=${TARGET} mode=${RUN_MODE_ARG} PREFIX_ROOT=${PREFIX_ROOT}"
case "${TARGET}" in
  pack)
    build_pack
    ;;
  protenix)
    build_protenix
    ;;
  pxdesign)
    build_pxdesign
    ;;
  all)
    build_pack
    build_protenix
    build_pxdesign
    ;;
  *)
    echo "${TAG} unknown target: ${TARGET}" >&2
    exit 2
    ;;
esac

echo "${TAG} done target=${TARGET}"
