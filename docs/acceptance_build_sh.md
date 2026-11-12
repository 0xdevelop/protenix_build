# `./build.sh` 第二阶段验收（2026-11-12）

层级：脚本能跑 / zip 生成 / GPU 真推理冒烟 / **从零 prefix 安装**。未做 `systemctl start`（规则禁止本机装 unit）。

## 环境
- aarch64，NVIDIA GB10，CUDA 13.0，Go 1.27.4（`~/.local/go`），uv + Python 3.14
- 版本唯一来源：`gen_pre_build_config_*.yaml`（`project.version=v0.0.1`）

## `./build.sh all`（幂等跳过路径，既有 prefix）

```bash
./build.sh --help          # rc=0
/usr/bin/time -f 'WALL=%e rc=%x' ./build.sh all
# 第 1 次（4a6b48c 前）：WALL=4.62 rc=0 — Go 打包 + skip 已就绪 prefix
# 第 2 次：WALL=0.19 rc=0 — skip go + skip prefix
```

产物：`build/upload_tmp_dir/{protenix,pxdesign}_linux_{amd64,arm64}_release_v0.0.1.zip`

## 缺口补验：`PREFIX_ROOT` 从零安装（2026-11-12）

不触碰已校验的 `prefix/protenix`、`prefix/pxdesign`（安装前后 pip-freeze sha256 与 venv mtime 未变）。

```bash
FRESH=/home/certa/workspace/protenix_build_fresh_prefix
mkdir -p "$FRESH"
/usr/bin/time -f 'WALL=%e rc=%x' \
  env PREFIX_ROOT="$FRESH" WEIGHTS_REUSE_FROM="$PWD/prefix" ./build.sh all
# WALL=695.40 rc=0
# - Go 双 arch 实际打包（非 skip）
# - 实际执行 install_prefix_protenix.sh / install_prefix_pxdesign.sh → 新 venv
# - 权重经 scripts/weights_reuse.sh 硬链接并校 size（同 inode）；缺则下载
```

日志：`tmp/fresh_build_all.log`（可删；命令可复现）。

### 新 prefix 冒烟（`scripts/smoke_*.sh`）

```bash
PREFIX_ROOT="$FRESH" bash scripts/smoke_protenix.sh
# start 2026-11-12 12:55:47 +0800
# end   2026-11-12 12:58:34 +0800 rc=0 wall=167.36
# cif_count=5  NO_ERR  gpu_max_util=96%

PREFIX_ROOT="$FRESH" bash scripts/smoke_pxdesign.sh
# start 2026-11-12 12:58:39 +0800
# end   2026-11-12 13:00:11 +0800 rc=0 wall=91.48
# cif_count=4  NO_ERR  gpu_max_util=96%
```

临时目录验收后可删除：`rm -rf /home/certa/workspace/protenix_build_fresh_prefix`。

## 既有 prefix 冒烟（复现入口已迁入 `scripts/`）

```bash
bash scripts/smoke_protenix.sh
# （历史）start 2026-11-12 12:07:59 +0800 → wall=165.678 rc=0 cif=5 NO_ERR gpu=96%
# 作业：prefix/protenix/jobs/buildsh_smoke/

bash scripts/smoke_pxdesign.sh
# （历史）wall=86.311 rc=0 cif=4 NO_ERR gpu=96%
# 作业：prefix/pxdesign/jobs/buildsh_smoke/
```

`tmp/smoke_*.sh` 已废弃；删除 `tmp/` 后仍用上面两条复现。

## BUILD_INFO 与 HEAD

- 工作区 dirty：`commit=<HEAD>-dirty`、`dirty=1`，不写 ready stamp。
- 交付流程：先 `git commit`，再 `FORCE_GO=1 ./build.sh go`，使 zip 内 `commit` / `commit_head` 等于 HEAD 且 `dirty=0`。
- 从零安装当次打包（提交 `641a446`）：`commit=641a4462dfdbad0b18849a6e4884bf9a8e0f89ad` `dirty=0`（与当时 HEAD 一致）。最终交付包在文档提交后再 `FORCE_GO=1` 重打，以最终 HEAD 为准。

## 分步入口
- `./build.sh go` / `protenix` / `pxdesign` / `all`
- `PREFIX_ROOT` / `WEIGHTS_REUSE_FROM` / `FORCE_GO=1` / `FORCE_PROTENIX=1` / `FORCE_PXDESIGN=1`
