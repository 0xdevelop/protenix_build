# 发布包自包含验收（2026-11-12）

层级：zip 自包含安装 + GPU 真推理冒烟。未做 `systemctl start`（规则禁止本机装 unit）。

## 环境

- aarch64，NVIDIA GB10，CUDA 13.0，uv + Python 3.14
- 验收目录：`/home/certa/workspace/pkg_accept`（结束后已删除）
- 权重：`WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix`（硬链接，校 size；默认 `prefix/` 未改）

## 打包

```bash
# 代码已提交后
FORCE_GO=1 ./build.sh go
# WALL≈8s rc=0
# arm64 zip：protenix ≈61MB，pxdesign ≈17MB（含 git archive 源码快照）
```

BUILD_INFO（arm64，打包提交当时）：`commit` / `commit_head` 与当时 HEAD 一致、`dirty=0`，并含 `src_sha=`。

## 包内自包含检查

```bash
mkdir -p /home/certa/workspace/pkg_accept && cd /home/certa/workspace/pkg_accept
unzip protenix_linux_arm64_release_v0.0.1.zip
unzip pxdesign_linux_arm64_release_v0.0.1.zip
rg -n 'build_srcs|/home/certa/workspace/protenix_build' \
  protenix/scripts protenix/install_protenix.sh \
  pxdesign/scripts pxdesign/install_pxdesign.sh
# → 无命中（GREP_CLEAN）
# 含 src/<product>/ + src/SRC_SHA、constraints/、scripts/weights_reuse.sh
# 不含 scripts/repo_src_defaults.sh
```

## 安装（仅包内路径）

```bash
cd /home/certa/workspace/pkg_accept/protenix
PREFIX_ROOT=/home/certa/workspace/pkg_accept/prefix \
WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix \
  bash scripts/install_prefix_protenix.sh
# WALL=41.39 rc=0；源码来自包内 src/protenix @ 85767b811c40
# 权重 hardlink 同 inode；ckpt size=1475950125

PROTENIX_INSTALL_PREFIX=$PREFIX_ROOT/protenix bash install_protenix.sh

cd /home/certa/workspace/pkg_accept/pxdesign
PREFIX_ROOT=/home/certa/workspace/pkg_accept/prefix \
WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix \
  bash scripts/install_prefix_pxdesign.sh
# WALL=29.23 rc=0；源码来自包内 src/pxdesign @ f788441313c8
# pxdesign ckpt size=556554618；af2 params size=373069562；同 inode

PXDESIGN_INSTALL_PREFIX=$PREFIX_ROOT/pxdesign bash install_pxdesign.sh
```

## 冒烟

### Protenix

```bash
# 输入：包内 examples_ref/input.json
# start 2026-11-12 16:44:25 +0800 → end 16:47:15
# rc=0 wall=169.57 cif_count=5 NO_ERR gpu_max_util=96%
```

### PXDesign

首次用当时不完整的 `examples_ref/`（缺 `msa/`）失败：`FileNotFoundError: .../msa/PDL1/0/pairing.a3m`。  
包内完整示例在 `src/pxdesign/examples/`（git archive）；改用该目录后通过。随后已修 `build.sh`：`examples_ref` 改为整树拷贝（含 msa）。

```bash
# 输入：包内 src/pxdesign/examples/（含 msa）
# start 2026-11-12 16:48:44 +0800 → end 16:51:01
# rc=0 wall=137.60 cif_count=5 NO_ERR gpu_max_util=96%
```

## 默认 prefix

安装前后 `prefix/protenix/venv`、`prefix/pxdesign/venv` mtime 仍为 2026-11-11，未改动。

## 清理

```bash
rm -rf /home/certa/workspace/pkg_accept
```
