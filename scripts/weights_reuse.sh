#!/bin/bash
# 权重复用：从已校验源硬链接（失败则拷贝），并校验 size；拷贝路径再校 sha256。
# 由 install_prefix_*.sh source；调用方须已定义 die。
# 用法：
#   seed_tree_verified <源目录> <目标目录>
#   link_or_copy_verified <源文件> <目标文件>

link_or_copy_verified() {
  local src="$1" dst="$2"
  local ss sd hs hd
  [[ -f "${src}" ]] || die "weights reuse source missing: ${src}"
  ss="$(stat -c%s "${src}")"
  [[ "${ss}" -gt 0 ]] || die "weights reuse source empty: ${src}"
  mkdir -p "$(dirname "${dst}")"
  if [[ -e "${dst}" ]]; then
    sd="$(stat -c%s "${dst}")"
    if [[ "${ss}" == "${sd}" ]] && [[ "$(stat -c%i "${src}")" == "$(stat -c%i "${dst}")" ]] \
      && [[ "$(stat -c%d "${src}")" == "$(stat -c%d "${dst}")" ]]; then
      return 0
    fi
    if [[ "${ss}" == "${sd}" ]]; then
      hs="$(sha256sum "${src}" | awk '{print $1}')"
      hd="$(sha256sum "${dst}" | awk '{print $1}')"
      [[ "${hs}" == "${hd}" ]] && return 0
    fi
    die "weights reuse refuse overwrite mismatched dest: ${dst} (src_size=${ss} dst_size=${sd:-missing})"
  fi
  if ln "${src}" "${dst}" 2>/dev/null; then
    sd="$(stat -c%s "${dst}")"
    [[ "${ss}" == "${sd}" ]] || die "hardlink size mismatch: ${dst}"
    return 0
  fi
  cp -f "${src}" "${dst}" || die "copy failed: ${src} -> ${dst}"
  sd="$(stat -c%s "${dst}")"
  [[ "${ss}" == "${sd}" ]] || die "copy size mismatch: ${dst} (${sd} != ${ss})"
  hs="$(sha256sum "${src}" | awk '{print $1}')"
  hd="$(sha256sum "${dst}" | awk '{print $1}')"
  [[ "${hs}" == "${hd}" ]] || die "copy sha256 mismatch: ${dst}"
}

seed_tree_verified() {
  local src_dir="$1" dst_dir="$2" f rel n=0
  [[ -d "${src_dir}" ]] || die "weights reuse tree missing: ${src_dir}"
  mkdir -p "${dst_dir}"
  while IFS= read -r -d '' f; do
    rel="${f#"${src_dir}"/}"
    link_or_copy_verified "${f}" "${dst_dir}/${rel}"
    n=$((n + 1))
  done < <(find "${src_dir}" -type f -print0)
  echo "[weights_reuse] seeded ${n} files ${src_dir} -> ${dst_dir}"
}
