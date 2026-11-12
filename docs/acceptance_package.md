# 发布包验收（命令行工具闭环）

机器：spark-901f（NVIDIA GB10，aarch64，统一内存 121GB，CUDA 13.0）。验收目录 `/home/certa/pkg_accept`（验收后删除），不碰仓库内已验证的 `prefix/`（权重用 `WEIGHTS_REUSE_FROM` 硬链接复用，同 inode）。
提交对齐：先提交代码，再 `FORCE_PACK=1 ./build.sh pack`，zip 内 `BUILD_INFO.txt` 的 `commit == HEAD` 且 `dirty=0`。

## 包自包含检查

对 arm64 两个包解压后的安装脚本、`scripts/`、`bin/`、`conf/`（不含 `src/`）执行：

```
grep -rn "build_srcs|/home/certa/workspace/protenix_build" ...   → 无命中
```

包内结构：`install_<app>.sh`、`README.md`、`bin/<app>-run`、`conf/<app>.env`、`scripts/{install_common,install_prefix_<app>,weights_reuse}.sh`、`deps/`、`patches/`（仅 pxdesign）、`src/<app>/` + `src/SRC_SHA`、`examples/`、`BUILD_INFO.txt`。

## Protenix（commit c7198fa）

| 步骤 | 命令 | 结果 |
|------|------|------|
| 安装前状态 | `install_protenix.sh status` | 未安装，rc=1 |
| 从零安装 | `PROTENIX_PREFIX=... WEIGHTS_REUSE_FROM=... install_protenix.sh install` | rc=0（uv 缓存命中约 24s；冷环境此前实测约 11.5min）。新建 Python 3.14.10 venv，装 torch 2.14.1+cu130 等；权重硬链接复用 |
| 状态 | `install_protenix.sh status` | 当前版本 v0.0.1-c7198fa2c045，状态：可运行 |
| 单次预测 | `bin/protenix-run pred -i examples/input.json -o out --use_msa false -s 101` | wall=166.8s rc=0 cif=5 无 ERR |
| 冒烟（smoke_protenix.sh，8f2aa 结构相同包） | 同上 | wall=164.3s rc=0 cif=5 无 ERR GPU峰值=96% 内存峰值=23.4GB |
| update（同包同版本） | `install_protenix.sh update` | “已是该版本，无需升级”，仍可运行 |
| update（改一次提交后重打的包） | `install_protenix.sh update` | 升级 v0.0.1-8f2aa… → v0.0.1-2a8d…，rc=0，状态：可运行；previous 保留 |
| rollback | `install_protenix.sh rollback` | 回退 2a8d… → 8f2aa…，状态：可运行 |
| uninstall（保留数据） | `install_protenix.sh uninstall` | 删除 releases/bin/current/previous；保留 conf、data |
| uninstall --purge | `install_protenix.sh uninstall --purge` | 整个安装目录删除 |

## PXDesign（commit c7198fa）

| 步骤 | 命令 | 结果 |
|------|------|------|
| 从零安装 | `PXDESIGN_PREFIX=... WEIGHTS_REUSE_FROM=... install_pxdesign.sh install` | rc=0（约 34s，权重复用）。独立 venv（Python 3.14），钉死 Protenix v0.5.0+pxd 链 |
| 状态 | `install_pxdesign.sh status` | 当前版本 v0.0.1-c7198fa2c045，状态：可运行 |
| 冒烟（smoke_pxdesign.sh） | `bin/pxdesign-run pipeline --preset preview -i examples/PDL1_quick_start.yaml -o out --N_sample 2` | wall=93.8s rc=0 cif=5 无 ERR GPU峰值=96% 内存峰值=18.7GB |
| uninstall --purge | `install_pxdesign.sh uninstall --purge` | 安装目录删除 |

安装/卸载全程未改动仓库内 `prefix/`（venv mtime 停留在 2026-11-11；权重复用为同 inode 硬链接）。

## 并发测量（Protenix，同一示例，不同输出目录）

| 场景 | 每个作业墙钟 | 合计墙钟 | rc | cif | ERR | GPU峰值 | 内存峰值 |
|------|------|------|----|----|----|------|------|
| 单作业 | 166.8s | 166.8s | 0 | 5 | 无 | 96% | 23.4GB |
| 2 作业并发 | A=319.2s / B=319.3s | 319.3s | 0 / 0 | 5 / 5 | 无 / 无 | 96% | 37.2GB |

**结论：不是被强制串行。** 两个独立进程确实同时在跑（都在推进，内存足够：峰值 37GB 远低于 121GB）。但单个预测已把 GPU 算力吃到 96%，所以两个并发时每个各自变慢到约 2 倍，合计 319s ≈ 单作业的两倍——在这块 GPU 上并发几乎不提升吞吐。
含义：第三阶段 Go 服务引入队列的价值在于“有序调度、避免超额占用 GPU、对外稳定接口”，而不是在单卡上靠并发提速。真正的吞吐提升要靠多 GPU 或上游批处理，不是多开进程。
