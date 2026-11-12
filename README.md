# protenix_build

在 NVIDIA GB10（aarch64）等本机上原生安装并运行 [Protenix](https://github.com/bytedance/Protenix) 结构预测与 [PXDesign](https://github.com/bytedance/PXDesign) 蛋白设计。交付为发布 zip + systemd unit 模板；pip 依赖与模型权重按需联网获取。

## 前置条件

- 硬件：NVIDIA GB10 / aarch64（另有 amd64 包）
- 软件：CUDA 13 驱动与工具链（默认 `CUDA_HOME=/usr/local/cuda-13.0`，需有 `nvcc`、`nvidia-smi`）
- [uv](https://github.com/astral-sh/uv)，且能解析 **Python 3.14**
- 不需要 sudo、Docker、conda

## 获取

**方式 A — 源码构建**

```bash
git clone <本仓库> && cd protenix_build
git submodule update --init --recursive
chmod a+x gen_pre_build_config.sh build.sh
./gen_pre_build_config.sh all
./build.sh                  # Go 双 arch 打包 + 安装 prefix/protenix 与 prefix/pxdesign
# 或分步：./build.sh go | ./build.sh protenix | ./build.sh pxdesign
```

产物：

- `build/upload_tmp_dir/{protenix,pxdesign}_linux_{amd64|arm64}_release_v*.zip`（自包含：上游源码快照、constraints、安装脚本、Go 二进制）
- 默认 prefix：`prefix/protenix`、`prefix/pxdesign`（两套独立 venv）

可选：`PREFIX_ROOT=/其它路径 WEIGHTS_REUSE_FROM=/已有prefix根 ./build.sh all`（权重大小校验后硬链接/拷贝）。

**方式 B — 只用发布包**

下载对应 arch 的 zip，解压后按下方「安装」操作；包内已含源码快照与约束文件，**不必**再 clone 本仓库。

## 安装（发布包）

```bash
unzip protenix_linux_arm64_release_v*.zip
cd protenix
PREFIX_ROOT=/opt/protenix_prefix \
WEIGHTS_REUSE_FROM=/path/to/existing_prefix_root \
  bash scripts/install_prefix_protenix.sh
PROTENIX_INSTALL_PREFIX=$PREFIX_ROOT/protenix bash install_protenix.sh
```

```bash
unzip pxdesign_linux_arm64_release_v*.zip
cd pxdesign
PREFIX_ROOT=/opt/pxdesign_prefix \
WEIGHTS_REUSE_FROM=/path/to/existing_prefix_root \
  bash scripts/install_prefix_pxdesign.sh
PXDESIGN_INSTALL_PREFIX=$PREFIX_ROOT/pxdesign bash install_pxdesign.sh
```

不设 `WEIGHTS_REUSE_FROM` 时，公开权重会下载到 prefix；安装需能访问 PyPI 与 PyTorch cu130 索引。

## 跑一次 Protenix 预测

```bash
export PREFIX_ROOT=/opt/protenix_prefix   # 或仓库内 prefix
export PATH="$PREFIX_ROOT/protenix/venv/bin:$PATH"
export LAYERNORM_TYPE=torch
export SUPERVISOR_PREFIX="$PREFIX_ROOT/protenix"

mkdir -p "$PREFIX_ROOT/protenix/jobs/demo"
# 输入：发布包内 examples_ref/input.json
cp examples_ref/input.json "$PREFIX_ROOT/protenix/jobs/demo/input.json"

"$PREFIX_ROOT/protenix/bin/protenixd" pred \
  -i "$PREFIX_ROOT/protenix/jobs/demo/input.json" \
  -o "$PREFIX_ROOT/protenix/jobs/demo/output" \
  -n protenix_base_default_v1.0.0 \
  --use_msa false -s 101
```

成功条件：退出码 0、`output/` 下有 `.cif`、无 `ERR/` 目录、GPU 利用率 > 0。

## 跑一次 PXDesign 设计

```bash
export PREFIX_ROOT=/opt/pxdesign_prefix
export PATH="$PREFIX_ROOT/pxdesign/venv/bin:$PATH"
export LAYERNORM_TYPE=torch
export TOOL_WEIGHTS_ROOT="$PREFIX_ROOT/pxdesign/tool_weights"
export PROTENIX_DATA_ROOT_DIR="$PREFIX_ROOT/pxdesign/protenix_data"

JOB="$PREFIX_ROOT/pxdesign/jobs/demo"
mkdir -p "$JOB"
# 输入：发布包内 examples_ref/（含 yaml、cif、msa/）
cp -a examples_ref "$JOB/examples"

( cd "$JOB" && pxdesign pipeline --preset preview \
  -i ./examples/PDL1_quick_start.yaml \
  -o ./out \
  --N_sample 2 --num_workers 0 --use_fast_ln False \
  --load_checkpoint_dir "$PREFIX_ROOT/pxdesign/release_data/checkpoint" )
```

成功条件同上（看 `out/` 下的 CIF，且无 `ERR/`）。

## 模型版本 `PROTENIX_MODEL`

在 `conf/protenix.env`（或环境变量）中设置，默认 `protenix_base_default_v1.0.0`。

| 值 | 说明 |
|----|------|
| `protenix_base_default_v1.0.0`（默认） | 公开权重，安装时可自动下载 |
| `protenix-v2` | 需授权权重文件 `$PROTENIX_ROOT_DIR/checkpoint/protenix-v2.pt`；缺失则安装/运行失败，脚本不会尝试下载 |

## 作为 systemd 服务运行

Unit 为 **Type=oneshot**（冒烟预检 / 批作业）。上游无常驻服务入口。

**用户级（无需 sudo）**

```bash
# 以 Protenix 为例；先保证 install_protenix.sh 已把 unit 拷到 prefix/systemd/
mkdir -p ~/.config/systemd/user
INSTALL_SYSTEMD=1 SYSTEMD_PATH="$HOME/.config/systemd/user" \
  PROTENIX_INSTALL_PREFIX="$PREFIX_ROOT/protenix" bash install_protenix.sh
systemctl --user daemon-reload
systemctl --user start protenix.service          # 冒烟预检
systemctl --user start protenix-oneshot.service  # 批作业（参数见 conf/protenix.env）
journalctl --user -u protenix-oneshot.service -e
```

**系统级（需管理员把 unit 装到 `/etc/systemd/system`）**

```bash
INSTALL_SYSTEMD=1 SYSTEMD_PATH=/etc/systemd/system \
  PROTENIX_INSTALL_PREFIX="$PREFIX_ROOT/protenix" bash install_protenix.sh
sudo systemctl daemon-reload
sudo systemctl start protenix-oneshot.service
sudo journalctl -u protenix-oneshot.service -e
```

PXDesign 同理（`pxdesign.service` / `pxdesign-oneshot.service`）。

## 常见问题

| 现象 | 处理 |
|------|------|
| `uv` / Python 3.14 找不到 | 安装 uv 后确认 `uv python list` 含 3.14 |
| `nvcc` 缺失 | 安装 CUDA 13 toolkit，或设置正确的 `CUDA_HOME` |
| 退出码 0 但只有 `ERR/`、无 CIF | 按失败样本处理；检查输入与依赖，勿只看退出码 |
| GPU 利用率一直 0 | 检查驱动、`nvidia-smi`、`torch.cuda.is_available()` |
| `PROTENIX_MODEL=protenix-v2` 失败 | 放入授权权重，或改回 v1 |
| PXDesign 报 layernorm / AF2 相关错误 | 确认 `LAYERNORM_TYPE=torch`、`--use_fast_ln False`、`--num_workers 0` |

更多设计说明见 `docs/design.md`；机器验收记录见 `docs/acceptance_*.md`。
