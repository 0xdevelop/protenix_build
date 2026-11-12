# `./build.sh` 第二阶段验收（2026-11-12）

层级：脚本能跑 / zip 生成 / GPU 真推理冒烟。未做 `systemctl start`（规则禁止本机装 unit）。

## 环境
- aarch64，NVIDIA GB10，CUDA 13.0，Go 1.27.4（`~/.local/go`），uv + Python 3.14
- 版本唯一来源：`gen_pre_build_config_*.yaml`（`project.version=v0.0.1`）

## `./build.sh all`（两次）

```bash
./build.sh --help          # rc=0
/usr/bin/time -f 'WALL=%e rc=%x' ./build.sh all
# 第 1 次：WALL=4.62 rc=0
#   - 构建并打包 linux/amd64 + linux/arm64 共 4 个 zip
#   - skip protenix / pxdesign prefix（已就绪）
/usr/bin/time -f 'WALL=%e rc=%x' ./build.sh all
# 第 2 次：WALL=0.19 rc=0
#   - skip go linux/amd64 + linux/arm64
#   - skip protenix / pxdesign prefix
```

产物：`build/upload_tmp_dir/{protenix,pxdesign}_linux_{amd64,arm64}_release_v0.0.1.zip`

## Protenix 最小推理冒烟

```bash
bash tmp/smoke_protenix.sh
# start 2026-11-12 12:07:59 +0800
# end   2026-11-12 12:10:44 +0800 rc=0 wall=165.678
# cif_count=5  NO_ERR  gpu_max_util=96%
```

作业目录：`prefix/protenix/jobs/buildsh_smoke/`（`protenixd pred`，模型 `protenix_base_default_v1.0.0`，`--use_msa false -s 101`）

## PXDesign quick_start 冒烟

```bash
bash tmp/smoke_pxdesign.sh
# 第 1 次失败：只拷了 yaml、缺 5o45.cif/msa，且 cwd 不对 → 已修脚本后重跑
# 第 2 次：start 2026-11-12 12:11:28 +0800
#          end   2026-11-12 12:12:54 +0800 rc=0 wall=86.311
#          cif_count=4  NO_ERR  gpu_max_util=96%
```

作业目录：`prefix/pxdesign/jobs/buildsh_smoke/`（复用 `jobs/run2/examples`，独立 `prefix/pxdesign` venv，未与 protenix 合并）

## 分步入口（已实现，未逐个计时）
- `./build.sh go` / `protenix` / `pxdesign` / `all`
- 强制重做：`FORCE_GO=1` / `FORCE_PROTENIX=1` / `FORCE_PXDESIGN=1`
