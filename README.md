# protenix_build

把 [Protenix](https://github.com/bytedance/Protenix)（结构预测）和 [PXDesign](https://github.com/bytedance/PXDesign)（蛋白设计）打成两个可在 NVIDIA GPU 机器上原生安装的**命令行工具**。交付物是发布 zip；解压后用 `install_<app>.sh` 完成安装、升级、回退、卸载。不用 Docker、conda，不需要 sudo。

> 常驻服务（队列、并发、对外接口）是后续阶段的事，本阶段不含。这里两个产物都是命令行工具。

## 交付物

每个 arch 两个 zip，各自独立：

- `protenix_linux_{amd64,arm64}_release_v*.zip`
- `pxdesign_linux_{amd64,arm64}_release_v*.zip`

每个 zip 解压后：

```
install_<app>.sh        安装/升级/回退/卸载/状态
README.md               使用说明
bin/<app>-run           安装后复制到安装目录的命令入口
conf/<app>.env          运行配置模板
scripts/                安装脚本（install_prefix_*、install_common、weights_reuse）
deps/ patches/          依赖版本覆盖与运行期补丁
src/<app>/ src/SRC_SHA  上游源码快照（不依赖本仓库）
examples/               示例输入
BUILD_INFO.txt          版本、提交、源码 sha
```

安装后目录（默认 `~/.local/share/<app>`）：`bin/<app>-run`、`conf/`、`data/`（权重）、`releases/<版本>/`（每版一套 venv，`current`/`previous` 符号链接指向）。

## 前置条件

- NVIDIA 驱动 + CUDA 13 工具链（`nvidia-smi`、`nvcc`，默认 `CUDA_HOME=/usr/local/cuda-13.0`）
- [uv](https://github.com/astral-sh/uv)，能解析 Python 3.14
- 公网访问（pip 依赖、模型权重）

## 用发布包安装

```bash
unzip protenix_linux_arm64_release_v*.zip && cd protenix
./install_protenix.sh install
# PXDesign 同理
unzip pxdesign_linux_arm64_release_v*.zip && cd pxdesign
./install_pxdesign.sh install
```

换安装目录：`PROTENIX_PREFIX=/dir`（或 `PXDESIGN_PREFIX=/dir`）。
复用已有权重跳过下载：`WEIGHTS_REUSE_FROM=/已有/prefix/根`。
详细步骤（跑一次预测/设计、切模型、FAQ）见各包内 `README.md`。

## 从源码构建发布包

```bash
git clone <本仓库> && cd protenix_build
git submodule update --init --recursive
./gen_pre_build_config.sh all
./build.sh            # 双 arch 发布包 + 本机安装 prefix/protenix、prefix/pxdesign
```

`build.sh` 子命令：

| 命令 | 作用 |
|------|------|
| `./build.sh pack` | 只打发布包到 `build/upload_tmp_dir/`（不跑 GPU/pip） |
| `./build.sh protenix` / `pxdesign` | 只在本机装/校验对应 prefix（uv + Python 3.14 + torch cu130） |
| `./build.sh all`（默认） | 先打包，再装两个 prefix |

幂等：已就绪的步骤跳过；`FORCE_PACK=1` / `FORCE_PROTENIX=1` / `FORCE_PXDESIGN=1` 强制重做。
发布包交付前先提交、再 `FORCE_PACK=1 ./build.sh pack`，让 `BUILD_INFO.txt` 的 commit 对齐 HEAD。
发版（打 tag、上传）走 `git_tag.sh` 与 GitHub Actions，`build.sh` 只负责构建。

## 命令入口

安装后用 `<安装目录>/bin/<app>-run`：

```bash
~/.local/share/protenix/bin/protenix-run pred -i input.json -o out --use_msa false -s 101
~/.local/share/pxdesign/bin/pxdesign-run pipeline --preset preview -i task.yaml -o out --N_sample 2
```

成功条件：退出码 0、输出目录有 `.cif`、无 `ERR/`、GPU 有占用。

## 两套环境不可合并

`protenix` 用最新上游；`pxdesign` 链依赖官方钉死的 Protenix v0.5.0+pxd。两者是独立 venv，分开安装、互不影响。

更多实现口径见 `docs/design.md`；机器验收记录见 `docs/acceptance_*.md`。
