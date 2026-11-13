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

## PXDesign 生命周期、故障与取消（commit 7efffda，2026-11-13）

机器仍是 spark-901f。验收目录 `/home/certa/pkg_accept_pxd`（验收后删除），不碰仓库内已验证的 `prefix/`。发布包为当日干净打包的 `pxdesign_linux_arm64_release_v0.0.1.zip`（`BUILD_INFO.commit=7efffdacf77d85beed0bd37ec5a04d763cd57ec4`，`dirty=0`）。权重复用：`WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix`。PyPI 镜像：`https://mirrors.aliyun.com/pypi/simple`。原始记录：`tmp/handoff-followup/pxdesign-lifecycle-cancel-result.txt`。开始时 GPU 上有本机 ComfyUI 进程驻留约 170MiB、利用率为 0%，未结束该进程。

包内安装脚本、`scripts/`、`bin/`、`conf/`、`README.md`、`BUILD_INFO.txt`（不含 `src/`）对 `build_srcs` 和 `/home/certa/workspace/protenix_build` 无命中。

| 步骤 | 命令 / 做法 | 结果 |
|------|-------------|------|
| 安装前状态 | `install_pxdesign.sh status` | 未安装，rc=1 |
| 从零安装 | `PXDESIGN_PREFIX=... WEIGHTS_REUSE_FROM=... install_pxdesign.sh install` | rc=0，墙钟 42s；版本 `v0.0.1-7efffdacf77d`，状态：可运行。AF2 `params_model_1.npz` 与仓库 prefix 同 inode（`66306:9830416`，373069562 B） |
| update（同包同版本） | `install_pxdesign.sh update` | “已是该版本 v0.0.1-7efffdacf77d，无需升级”，current 不变，rc=0 |
| update（故意失败） | 解压副本里把 `install_prefix_pxdesign.sh` 改成 `exit 42`，并把测试目录 `BUILD_INFO.commit` 改为 `brokenfail000111222333444555` 后执行 update | rc=1；“版本 v0.0.1-brokenfail00 构建失败（rc=42），已删除半成品；当前版本未改动”。之后 status 仍为可运行，`v0.0.1-7efffdacf77d` |
| update（不同 release id） | 本机没有第二份官方 PXDesign zip。用同一 7efffda 包的解压副本，只改测试目录 `BUILD_INFO.commit=testdrive0001deadbeefcafebabe`（`pkg_release_id` 取前 12 位，得到 `v0.0.1-testdrive000`）。**不是第二次真实发版。** | rc=0，墙钟 47s；current=`v0.0.1-testdrive000`，previous=`v0.0.1-7efffdacf77d`，状态：可运行；配置保留 |
| rollback | `install_pxdesign.sh rollback` | rc=0；current 回到 `v0.0.1-7efffdacf77d`，previous=`v0.0.1-testdrive000`，状态：可运行 |
| 故障：缺输入 | `pxdesign-run pipeline --preset preview -i ./no-such.yaml -o ./out --N_sample 2` | rc=2，0.041s，cif=0，无 ERR。提示：`Invalid value for '--input' / '-i': File './no-such.yaml' does not exist.` |
| 故障：非法 YAML | 同样入口，输入为无法解析的 YAML | rc=1，9.315s，cif=0，无 ERR。上游 `ValueError: Error parsing YAML file: mapping values are not allowed here` |
| 取消：两路并发 preview，对其中一路的启动子壳发 SIGTERM | 输入先复制到各作业目录，独立 `TMPDIR`/`out`。GPU 利用率在约 22s 见到 94% 后再等 15s，向 `cancel-kill` 的 bash 子壳 PID 发 SIGTERM（8s 内该 PID 退出，未升级 SIGKILL） | 另一路 `cancel-keep`：rc=0，墙钟 138.4s，cif=4，无 ERR，GPU 峰值 96%，内存峰值 28999 MiB，输入哈希不变。被发信号的一路：子壳 rc=143，但上游 Python 未被带走，日志写到 `Finish all designs!`，cif=5，无 ERR，输入未改。安装目录共享权重快照变更=0 |
| uninstall（保留数据） | `install_pxdesign.sh uninstall` | rc=0；删除 releases/bin/current/previous；保留 conf、data、`.installed_by` |
| uninstall --purge | `install_pxdesign.sh uninstall --purge` | rc=0；整个安装目录删除 |

安装 / 升级 / 回退 / 卸载全程未改动仓库内 `prefix/`（venv mtime 仍为 2026-11-11 16:51:58 +0800；权重复用为同 inode 硬链接）。验收目录已删除。

**取消的实测边界：** 对作业启动用的 bash 子壳发 SIGTERM，只能让该包装 PID 退出（rc=143），不能当作已取消正在跑的 PXDesign pipeline。另一路任务仍能正常完成，说明这一层隔离成立；第三阶段常驻服务若要提供可验收的取消，必须跟踪并终止实际上游进程或进程组。无证据不报生产级取消。结果仍按退出码、CIF、有无 ERR 判断，不用位对比。
