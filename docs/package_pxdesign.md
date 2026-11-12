# PXDesign 命令行工具

在一台装了 NVIDIA GPU（如 GB10 / aarch64）的机器上，对给定靶点做蛋白 binder 设计。本包是命令行工具，不是常驻服务。

## 前置条件

- NVIDIA 驱动与 CUDA 13 工具链（有 `nvidia-smi`、`nvcc`，默认 `CUDA_HOME=/usr/local/cuda-13.0`）
- [uv](https://github.com/astral-sh/uv)，且能解析 Python 3.14
- 能访问公网（装 pip 依赖、下载权重与 AF2/MPNN 等工具权重）
- 不需要 sudo、Docker、conda

## 安装

```bash
unzip pxdesign_linux_arm64_release_v*.zip
cd pxdesign
./install_pxdesign.sh install
```

默认装到 `~/.local/share/pxdesign`。换目录：`PXDESIGN_PREFIX=/your/dir ./install_pxdesign.sh install`。
复用已有机器上的权重（跳过下载）：`WEIGHTS_REUSE_FROM=/已有/prefix/根 ./install_pxdesign.sh install`。

首次安装会下载约 4GB 权重（PXDesign、Protenix v0.5.0、AF2 两个参数文件、ProteinMPNN、CCD 缓存）。
命令入口是 `~/.local/share/pxdesign/bin/pxdesign-run`。

## 跑一次设计

```bash
RUN=~/.local/share/pxdesign/bin/pxdesign-run
mkdir -p ~/pxd_job
cp -a examples ~/pxd_job/examples
cd ~/pxd_job
"$RUN" pipeline --preset preview -i ./examples/PDL1_quick_start.yaml -o ./out --N_sample 2
```

`pxdesign-run` 会自动补上权重目录、`--use_fast_ln False`、`--num_workers 0`。
成功的判断：退出码 0、`out/` 下有 `.cif`、没有 `out/ERR/`、运行时 GPU 有占用。

## 升级 / 回退 / 卸载 / 查看状态

```bash
./install_pxdesign.sh update            # 在新版本解压目录里执行；配置和权重保留，失败不影响当前版本
./install_pxdesign.sh rollback          # 回退上一版本
./install_pxdesign.sh status            # 版本、提交、是否可运行
./install_pxdesign.sh uninstall         # 卸载，保留配置和权重
./install_pxdesign.sh uninstall --purge # 连配置和权重一起删
```

## 常见问题

| 现象 | 处理 |
|------|------|
| 找不到 uv 或 Python 3.14 | 装 uv 后确认 `uv python list` 含 3.14 |
| 找不到 nvcc | 装 CUDA 13 工具链，或把 `CUDA_HOME` 指对 |
| 退出码 0 但只有 `ERR/`、没有 CIF | 按失败任务排查输入 |
| GPU 利用率一直 0 | 查驱动、`nvidia-smi`、`torch.cuda.is_available()` |
| layernorm / AF2 相关报错 | 入口默认已带 `--use_fast_ln False --num_workers 0`；确认没被手动覆盖 |
