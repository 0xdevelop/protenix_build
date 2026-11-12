#!/bin/bash
# install_<app>.sh 的共用逻辑：install / update / rollback / uninstall / status。
# 调用方先设置：APP（protenix|pxdesign）、PKG（发布包解压目录）、CLI（上游命令名），再 source 本文件并调用 main "$@"。
#
# 安装目录（默认 ~/.local/share/<app>，用 <APP>_PREFIX 覆盖）：
#   bin/<app>-run          命令入口
#   conf/<app>.env         运行配置（update 保留）
#   data/                  权重与数据（update 保留；uninstall 默认保留，--purge 删除）
#   releases/<版本>/        每个版本一份：venv、源码快照、安装日志
#   current -> releases/…  当前版本
#   previous -> releases/… 上一版本（rollback 用）
#   .installed_by          安装标记；uninstall --purge 只删带此标记的目录
set -euo pipefail

APP_UPPER="$(echo "${APP}" | tr 'a-z' 'A-Z')"
PREFIX_VAR="${APP_UPPER}_PREFIX"
PREFIX="${!PREFIX_VAR:-${HOME}/.local/share/${APP}}"
MARKER="${PREFIX}/.installed_by"
TAG="[install_${APP}]"

die() { echo "${TAG} 失败：$*" >&2; exit 1; }
say() { echo "${TAG} $*"; }

info_get() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1; }

pkg_release_id() {
  local bi="${PKG}/BUILD_INFO.txt" v c
  [[ -f "${bi}" ]] || die "发布包缺少 BUILD_INFO.txt：${bi}"
  v="$(info_get "${bi}" version)"
  c="$(info_get "${bi}" commit)"
  [[ -n "${v}" && -n "${c}" ]] || die "BUILD_INFO.txt 缺少 version 或 commit"
  echo "${v}-${c:0:12}${c#"${c%-dirty}"}"
}

link_target_name() { [[ -L "$1" ]] && basename "$(readlink "$1")" || true; }

# 原子切换符号链接
switch_link() {
  local name="$1" target="$2"
  ln -sfn "${target}" "${PREFIX}/.${name}.new"
  mv -T "${PREFIX}/.${name}.new" "${PREFIX}/${name}"
}

write_conf_if_missing() {
  local conf="${PREFIX}/conf/${APP}.env"
  mkdir -p "${PREFIX}/conf"
  if [[ -f "${conf}" ]]; then
    say "保留现有配置 ${conf}"
  else
    sed "s|@PREFIX@|${PREFIX}|g" "${PKG}/conf/${APP}.env" > "${conf}"
    say "写入配置 ${conf}"
  fi
}

# 在 releases/<id> 里构建 venv；失败时删掉这个半成品目录，不碰 current
build_release() {
  local id="$1" rel="${PREFIX}/releases/$1"
  if [[ -d "${rel}" ]]; then
    [[ "$(link_target_name "${PREFIX}/current")" != "${id}" ]] || die "内部错误：不应重建当前版本 ${id}"
    say "清理旧的同名版本目录 ${rel}"
    rm -rf "${rel}"
  fi
  mkdir -p "${rel}"
  say "构建版本 ${id} -> ${rel}"
  local rc=0
  case "${APP}" in
    protenix)
      PREFIX_ROOT="" PROTENIX_PREFIX="${rel}" PROTENIX_ENV_FILE="${PREFIX}/conf/${APP}.env" \
        bash "${PKG}/scripts/install_prefix_protenix.sh" || rc=$?
      ;;
    pxdesign)
      PREFIX_ROOT="" PXDESIGN_PREFIX="${rel}" PXDESIGN_DATA="${PREFIX}/data" \
        bash "${PKG}/scripts/install_prefix_pxdesign.sh" || rc=$?
      ;;
  esac
  if [[ ${rc} -ne 0 ]]; then
    rm -rf "${rel}"
    die "版本 ${id} 构建失败（rc=${rc}），已删除半成品；当前版本未改动"
  fi
  cp -f "${PKG}/BUILD_INFO.txt" "${rel}/BUILD_INFO.txt"
  [[ -d "${PKG}/examples" ]] && cp -a "${PKG}/examples" "${rel}/examples"
  verify_release "${rel}" || { rm -rf "${rel}"; die "版本 ${id} 自检失败，已删除；当前版本未改动"; }
}

verify_release() {
  local rel="$1"
  [[ -x "${rel}/venv/bin/${CLI}" ]] || { echo "${TAG} 缺少 ${rel}/venv/bin/${CLI}" >&2; return 1; }
  # 上游 import 时可能触发自定义内核，需与运行期一致的环境
  local help_args=(--help)
  [[ "${CLI}" == "pxdesign" ]] && help_args=(pipeline --help)
  env LAYERNORM_TYPE="${LAYERNORM_TYPE:-torch}" CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"     "${rel}/venv/bin/${CLI}" "${help_args[@]}" >/dev/null 2>&1     || { echo "${TAG} ${CLI} ${help_args[*]} 失败" >&2; return 1; }
}

install_entry() {
  mkdir -p "${PREFIX}/bin"
  cp -f "${PKG}/bin/${APP}-run" "${PREFIX}/bin/${APP}-run.new"
  chmod a+x "${PREFIX}/bin/${APP}-run.new"
  mv -f "${PREFIX}/bin/${APP}-run.new" "${PREFIX}/bin/${APP}-run"
}

prune_releases() {
  local cur prev d
  cur="$(link_target_name "${PREFIX}/current")"
  prev="$(link_target_name "${PREFIX}/previous")"
  for d in "${PREFIX}/releases"/*; do
    [[ -d "${d}" ]] || continue
    case "$(basename "${d}")" in
      "${cur}"|"${prev}") ;;
      *) say "删除更早的版本 $(basename "${d}")"; rm -rf "${d}" ;;
    esac
  done
}

cmd_install() {
  [[ ! -f "${MARKER}" || ! -L "${PREFIX}/current" ]] || die "已安装在 ${PREFIX}，升级请用 update"
  if [[ -d "${PREFIX}" && ! -f "${MARKER}" ]]; then
    local extra
    extra="$(find "${PREFIX}" -mindepth 1 -maxdepth 1 ! -name conf ! -name data | head -n1)"
    [[ -z "${extra}" ]] || die "${PREFIX} 已存在且不是本工具安装的（发现 ${extra}），换一个目录或先清空"
  fi
  local id
  id="$(pkg_release_id)"
  mkdir -p "${PREFIX}/releases"
  echo "${APP}" > "${MARKER}"
  write_conf_if_missing
  build_release "${id}"
  install_entry
  switch_link current "releases/${id}"
  say "安装完成：${APP} ${id}"
  say "命令入口：${PREFIX}/bin/${APP}-run"
}

cmd_update() {
  [[ -f "${MARKER}" && -L "${PREFIX}/current" ]] || die "${PREFIX} 下没有安装，请先 install"
  local id cur
  id="$(pkg_release_id)"
  cur="$(link_target_name "${PREFIX}/current")"
  if [[ "${id}" == "${cur}" ]] && verify_release "${PREFIX}/current"; then
    install_entry
    say "已是该版本 ${id}，无需升级"
    return 0
  fi
  if [[ "${id}" == "${cur}" ]]; then
    # 同版本但当前目录已损坏：换个目录名重建，成功后再切换
    id="${id}-$(date +%Y%m%d%H%M%S)"
    say "当前版本不可运行，重建为 ${id}"
  fi
  write_conf_if_missing
  build_release "${id}"
  install_entry
  switch_link previous "releases/${cur}"
  switch_link current "releases/${id}"
  prune_releases
  say "升级完成：${cur} -> ${id}（回退：$0 rollback）"
}

cmd_rollback() {
  [[ -f "${MARKER}" && -L "${PREFIX}/current" ]] || die "${PREFIX} 下没有安装"
  [[ -L "${PREFIX}/previous" && -d "${PREFIX}/previous/" ]] || die "没有可回退的上一版本"
  local cur prev
  cur="$(link_target_name "${PREFIX}/current")"
  prev="$(link_target_name "${PREFIX}/previous")"
  verify_release "${PREFIX}/releases/${prev}" || die "上一版本 ${prev} 自检失败，不回退"
  switch_link current "releases/${prev}"
  switch_link previous "releases/${cur}"
  say "已回退：${cur} -> ${prev}"
}

cmd_uninstall() {
  local purge=0
  [[ "${1:-}" == "--purge" ]] && purge=1
  [[ -f "${MARKER}" ]] || die "${PREFIX} 下没有本工具的安装标记，不做删除"
  [[ "$(cat "${MARKER}")" == "${APP}" ]] || die "${MARKER} 不属于 ${APP}，不做删除"
  case "$(cd "${PREFIX}" && pwd)" in
    /|"${HOME}") die "拒绝删除 ${PREFIX}" ;;
  esac
  if [[ ${purge} -eq 1 ]]; then
    rm -rf "${PREFIX}"
    say "已彻底删除 ${PREFIX}（含配置与权重）"
    return 0
  fi
  rm -rf "${PREFIX}/releases" "${PREFIX}/bin"
  rm -f "${PREFIX}/current" "${PREFIX}/previous" "${MARKER}"
  say "已卸载程序。保留：${PREFIX}/conf（配置）和 ${PREFIX}/data（权重）"
  say "连同配置和权重一起删除：$0 uninstall --purge"
}

cmd_status() {
  say "安装目录：${PREFIX}"
  if [[ ! -f "${MARKER}" || ! -L "${PREFIX}/current" ]]; then
    say "状态：未安装"
    return 1
  fi
  local bi="${PREFIX}/current/BUILD_INFO.txt"
  say "当前版本：$(link_target_name "${PREFIX}/current")"
  say "版本号：$(info_get "${bi}" version)  提交：$(info_get "${bi}" commit)  上游源码：$(info_get "${bi}" src_sha)"
  say "上一版本：$(link_target_name "${PREFIX}/previous" || true)"
  say "命令入口：${PREFIX}/bin/${APP}-run"
  say "配置：${PREFIX}/conf/${APP}.env"
  if [[ "${APP}" == "protenix" ]]; then
    say "模型：$(info_get "${PREFIX}/conf/${APP}.env" PROTENIX_MODEL)"
  fi
  if verify_release "${PREFIX}/current"; then
    say "状态：可运行"
  else
    say "状态：已安装但不可运行（重新执行 update 或 install）"
    return 2
  fi
}

usage() {
  cat <<USAGE
用法：./install_${APP}.sh <命令>
  install            首次安装到 \$${PREFIX_VAR}（默认 ~/.local/share/${APP}）
  update             用当前发布包升级已有安装；失败不影响原版本
  rollback           回到上一版本
  uninstall          卸载程序，保留配置和权重
  uninstall --purge  连同配置和权重一起删除
  status             查看安装状态
USAGE
}

main() {
  case "${1:-}" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    rollback)  cmd_rollback ;;
    uninstall) shift; cmd_uninstall "${1:-}" ;;
    status)    cmd_status ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}
