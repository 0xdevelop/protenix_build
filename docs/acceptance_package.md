# 发布包自包含验收（2026-11-12）

层级：zip 自包含安装 + GPU 真推理冒烟。未做 `systemctl start`（规则禁止本机装 unit）。

## 环境

- aarch64，NVIDIA GB10，CUDA 13.0，uv + Python 3.14
- 验收目录：`/home/certa/workspace/pkg_accept_b34d`（结束后删除；避免与并发目录冲突）
- 权重：`WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix`（硬链接，校 size；默认 `prefix/` 未改）

## 打包

```bash
# 代码提交后
FORCE_GO=1 ./build.sh go
# arm64 zip 含 git archive 源码快照 + deps + patches + examples_ref 整树
```

`BUILD_INFO`：`commit` / `commit_head` 等于最终 HEAD、`dirty=0`，并含 `src_sha=`。

## 包内自包含检查

```bash
unzip -q protenix_linux_arm64_release_v*.zip
unzip -q pxdesign_linux_arm64_release_v*.zip
grep -RIn 'build_srcs\|/home/certa/workspace/protenix_build' \
  protenix/scripts protenix/install_protenix.sh \
  pxdesign/scripts pxdesign/install_pxdesign.sh
# → GREP_CLEAN
# 含 src/<product>/ + src/SRC_SHA、deps/、patches/、scripts/weights_reuse.sh
# 不含 scripts/repo_src_defaults.sh
# pxdesign/examples_ref/msa/PDL1/0/pairing.a3m 存在
```

## 安装（仅包内路径）

```bash
cd .../pkg_accept_b34d/protenix
PREFIX_ROOT=.../pkg_accept_b34d/prefix \
WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix \
PYPI_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
  bash scripts/install_prefix_protenix.sh
# WALL≈23.5s rc=0；src=包内 src/protenix @ 85767b811c40
# ckpt size=1475950125，与源同 inode

PROTENIX_INSTALL_PREFIX=$PREFIX_ROOT/protenix bash install_protenix.sh

cd .../pkg_accept_b34d/pxdesign
PREFIX_ROOT=.../pkg_accept_b34d/prefix \
WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix \
PYPI_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
  bash scripts/install_prefix_pxdesign.sh
# WALL≈31.4s rc=0；src=包内 src/pxdesign @ f788441313c8
# pxdesign ckpt size=556554618，同 inode

PXDESIGN_INSTALL_PREFIX=$PREFIX_ROOT/pxdesign bash install_pxdesign.sh
```

## 冒烟

### Protenix（输入：包内 `examples_ref/input.json`）

```text
start 2026-11-12 16:48:43 +0800
end   2026-11-12 16:52:02 +0800
rc=0 wall=198.26 cif_count=5 NO_ERR gpu_max_util=96%
```

### PXDesign（输入：包内 `examples_ref/`，含 `msa/`）

```text
start 2026-11-12 16:53:42 +0800
end   2026-11-12 16:55:09 +0800
rc=0 wall=87.02 cif_count=6 NO_ERR gpu_max_util=96%
```

说明：`examples_ref` 曾只拷 yaml/json/cif、漏掉 `msa/`，会导致 `FileNotFoundError: pairing.a3m`；已改为整树拷贝后再验。

## 默认 prefix

安装前后未改动仓库内 `prefix/protenix`、`prefix/pxdesign`（权重复用为硬链接）。

## 清理

```bash
rm -rf /home/certa/workspace/pkg_accept /home/certa/workspace/pkg_accept_b34d
```
