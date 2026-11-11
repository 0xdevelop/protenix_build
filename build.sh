#!/bin/bash
# 只构建/打包，不 bump 版本、不打 tag、不 push。
# 用法：
#   bash build.sh [release|test|debug] [gen yaml | linux_amd64 | linux_arm64]
set -euo pipefail

project_path=$(cd "$(dirname "$0")" && pwd)
cd "${project_path}"

if ! command -v go >/dev/null 2>&1; then
  echo "[build] go not found in PATH" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "[build] zip not found in PATH" >&2
  exit 1
fi

RUN_MODE_ARG="${1:-release}"
CONFIG_ARG="${2:-}"

case "${RUN_MODE_ARG}" in
  release|test|debug) ;;
  linux_amd64|linux_arm64)
    CONFIG_ARG="${RUN_MODE_ARG}"
    RUN_MODE_ARG="release"
    ;;
  *)
    echo "Usage: bash build.sh [release|test|debug] [gen yaml | linux_amd64 | linux_arm64]" >&2
    exit 2
    ;;
esac

resolve_config() {
  local arg="$1"
  if [[ -z "${arg}" ]]; then
    local host_arch
    host_arch="$(uname -m)"
    case "${host_arch}" in
      x86_64|amd64) arg="linux_amd64" ;;
      aarch64|arm64) arg="linux_arm64" ;;
      *)
        echo "[build] cannot infer arch from ${host_arch}; pass gen yaml explicitly" >&2
        exit 1
        ;;
    esac
  fi
  case "${arg}" in
    linux_amd64) echo "gen_pre_build_config_linux_amd64.yaml" ;;
    linux_arm64) echo "gen_pre_build_config_linux_arm64.yaml" ;;
    *.yaml|*.yml)
      [[ -f "${arg}" ]] || { echo "[build] config not found: ${arg}" >&2; exit 1; }
      echo "${arg}"
      ;;
    *)
      echo "[build] unknown config selector: ${arg}" >&2
      exit 1
      ;;
  esac
}

CONFIG_FILE="$(resolve_config "${CONFIG_ARG}")"
[[ -f "${CONFIG_FILE}" ]] || { echo "[build] missing ${CONFIG_FILE}; run ./gen_pre_build_config.sh all first" >&2; exit 1; }

mkdir -p tmp
EXPORT_FILE="tmp/build_export_${CONFIG_FILE##*/}.env"
go run gen_pre_build_config.go -validate "${CONFIG_FILE}"
go run gen_pre_build_config.go -export "${CONFIG_FILE}" > "${EXPORT_FILE}"
# shellcheck disable=SC1090
source "${EXPORT_FILE}"

RUN_MODE="${RUN_MODE_ARG}"
BUILD_MODE_ROOT="${BUILD_ROOT}/${RUN_MODE}"
mkdir -p "${BUILD_MODE_ROOT}" "${UPLOAD_TMP_DIR}"

commit_hash="$(git show -s --format=%H 2>/dev/null || echo unknown)"
commit_date="$(git show -s --format='%ci' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S %z')"
build_time="$(date +'%Y-%m-%d_%H:%M:%S')"

echo "[build] project=${PROJECT_NAME} version=${PROJECT_VERSION} mode=${RUN_MODE} target=${GOOS_TARGET}/${GOARCH_TARGET}"
echo "[build] commit=${commit_hash} commit_date=${commit_date} build_time=${build_time}"
echo "[build] env_strategy=${ENV_STRATEGY} skip_prefix_install=${SKIP_PREFIX_INSTALL_IN_BUILD} delivery=${DELIVERY:-zip_and_systemd}"

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

  src="${!src_var}"
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
  mkdir -p "${out_dir}/bin" "${out_dir}/conf" "${out_dir}/systemd" "${out_dir}/scripts" "${out_dir}/docs"

  [[ -d "${superv_cmd}" ]] || { echo "[build] missing supervisor cmd path ${superv_cmd}" >&2; exit 1; }
  echo "[build] go build ${superv_bin} for ${GOOS_TARGET}/${GOARCH_TARGET}"
  CGO_ENABLED=0 GOOS="${GOOS_TARGET}" GOARCH="${GOARCH_TARGET}" \
    go build -trimpath -ldflags "-s -w" -o "${out_dir}/bin/${superv_bin}" "./${superv_cmd}"
  chmod a+x "${out_dir}/bin/${superv_bin}"

  cat > "${out_dir}/BUILD_INFO.txt" <<EOF
product=${name}
project=${PROJECT_NAME}
version=${PROJECT_VERSION}
run_mode=${RUN_MODE}
goos=${GOOS_TARGET}
goarch=${GOARCH_TARGET}
install_prefix=${INSTALL_PREFIX}
src_path=${src}
env_policy=${policy}
pinned_protenix_ref=${pinned_ref}
torch_hint=${torch_hint}
cli_name=${cli}
wrapper_name=${wrapname}
supervisor_bin=${superv_bin}
systemd_smoke=oneshot
systemd_batch=oneshot
commit=${commit_hash}
build_time=${build_time}
skip_prefix_install_in_build=${SKIP_PREFIX_INSTALL_IN_BUILD}
host_cuda=${HOST_CUDA:-}
product_python=${HOST_PYTHON_ANCHOR:-}/${PRODUCT_PYTHON_MIN:-}-${PRODUCT_PYTHON_MAX:-}
note=GPU/pip prefix install deferred to ${prefix_install} on target host
EOF

  for f in "${service}" "${oneshot}" "${envf}" "${wrapper}" "${install_sh}" "${prefix_install}"; do
    [[ -f "${f}" ]] || { echo "[build] missing ${f}" >&2; exit 1; }
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

  if [[ -d "${src}/examples" ]]; then
    mkdir -p "${out_dir}/examples_ref"
    find "${src}/examples" -maxdepth 2 \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -type f 2>/dev/null | head -20 | while read -r f; do
      rel="${f#${src}/examples/}"
      mkdir -p "${out_dir}/examples_ref/$(dirname "${rel}")"
      cp -f "${f}" "${out_dir}/examples_ref/${rel}"
    done || true
  fi

  cat > "${out_dir}/docs/README_RUN.md" <<EOF
# ${name} 包装包

- 冒烟：\`$(basename "${service}")\` Type=oneshot → \`bin/${superv_bin}\`（Go 预检；CLI/环境缺失即 failed）
- 批作业：\`$(basename "${oneshot}")\` Type=oneshot → \`bin/${superv_bin} <cli 参数>\`（退出码透传，journalctl 可查）
- 手动调试入口：\`bin/${wrapname}\`（shell wrapper，直接 exec 上游 CLI）
- 目标机：\`bash scripts/$(basename "${prefix_install}")\` 装 Python 3.14 + CUDA 13 栈（失败即非零退出，不跳过 GPU）
- 再：\`INSTALL_SYSTEMD=1 bash install_${name}.sh\`
- 冒烟：\`systemctl start $(basename "${service}")\`，结果看 \`systemctl status\` / \`journalctl -u\`

env_policy=${policy}
EOF

  if [[ "${SKIP_PREFIX_INSTALL_IN_BUILD}" != "1" ]]; then
    bash "${prefix_install}" || { echo "[build] prefix install failed for ${name}" >&2; exit 1; }
  else
    echo "[build] skip prefix GPU/pip install for ${name} (hook: ${prefix_install})"
  fi

  local zip_name="${name}_${GOOS_TARGET}_${GOARCH_TARGET}_${RUN_MODE}_${PROJECT_VERSION}.zip"
  local zip_path="${project_path}/${UPLOAD_TMP_DIR}/${zip_name}"
  rm -f "${zip_path}"
  ( cd "${BUILD_MODE_ROOT}" && zip -r "${zip_path}" "${subdir}" >/dev/null )
  echo "[build] packed ${UPLOAD_TMP_DIR}/${zip_name}"
}

for product in ${PRODUCT_NAMES}; do
  pack_one_product "${product}"
done

echo "[build] done. zips:"
ls -la "${UPLOAD_TMP_DIR}"/*_${GOOS_TARGET}_${GOARCH_TARGET}_${RUN_MODE}_${PROJECT_VERSION}.zip
