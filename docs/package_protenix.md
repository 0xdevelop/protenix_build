# Protenix 命令行工具

在一台装了 NVIDIA GPU（如 GB10 / aarch64）的机器上，从结构输入做蛋白结构预测。本包是命令行工具，不是常驻服务。

## 前置条件

- NVIDIA 驱动与 CUDA 13 工具链（有 `nvidia-smi`、`nvcc`，默认 `CUDA_HOME=/usr/local/cuda-13.0`）
- [uv](https://github.com/astral-sh/uv)，且能解析 Python 3.14（`uv python list` 里有 3.14）
- 能访问公网（装 pip 依赖、下载公开权重）
- 不需要 sudo、Docker、conda

## 安装

```bash
unzip protenix_linux_arm64_release_v*.zip
cd protenix
./install_protenix.sh install
```

默认装到 `~/.local/share/protenix`。换目录：`PROTENIX_PREFIX=/your/dir ./install_protenix.sh install`。
复用已有机器上的权重（跳过下载）：`WEIGHTS_REUSE_FROM=/已有/prefix/根 ./install_protenix.sh install`。

安装完成后命令入口是 `~/.local/share/protenix/bin/protenix-run`。

## 跑一次预测

```bash
RUN=~/.local/share/protenix/bin/protenix-run
mkdir -p ~/px_job
cp examples/input.json ~/px_job/input.json
"$RUN" pred -i ~/px_job/input.json -o ~/px_job/output --use_msa false -s 101
```

成功的判断：命令退出码为 0、`~/px_job/output/` 下有 `.cif` 文件、没有 `output/ERR/` 目录、运行时 `nvidia-smi` 看得到 GPU 占用。
（上游在个别样本出错时自身仍返回 0 并只写 `ERR/`；`protenix-run` 检测到 `ERR/` 会改为返回 3。）

## 切换模型

模型在 `~/.local/share/protenix/conf/protenix.env` 里的 `PROTENIX_MODEL`，默认 `protenix_base_default_v1.0.0`（公开权重）。
改成 `protenix-v2` 需要自备授权权重，放到 `conf` 里 `PROTENIX_ROOT_DIR` 指向的 `checkpoint/protenix-v2.pt`；没有就会直接报错，不会去下载。
也可一次性覆盖：`"$RUN" pred -n <模型名> -i ... -o ...`。

## 升级 / 回退 / 卸载 / 查看状态

```bash
# 升级：在新版本的解压目录里执行（配置和权重都保留；失败不影响当前版本）
./install_protenix.sh update
# 回退到上一个版本
./install_protenix.sh rollback
# 查看状态（版本、提交、模型、是否可运行）
./install_protenix.sh status
# 卸载（保留配置和权重）
./install_protenix.sh uninstall
# 连配置和权重一起删
./install_protenix.sh uninstall --purge
```

## 常见问题

| 现象 | 处理 |
|------|------|
| 找不到 uv 或 Python 3.14 | 装 uv 后确认 `uv python list` 含 3.14 |
| 找不到 nvcc | 装 CUDA 13 工具链，或把 `CUDA_HOME` 指对 |
| 退出码 0 但只有 `ERR/`、没有 CIF | 按失败样本排查输入；别只看退出码 |
| GPU 利用率一直 0 | 查驱动、`nvidia-smi`、`torch.cuda.is_available()` |
| 切 `protenix-v2` 报缺权重 | 放入授权权重，或改回 v1 |
