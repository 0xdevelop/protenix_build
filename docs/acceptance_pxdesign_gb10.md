# PXDesign 在 DGX Spark (GB10) 上的真实验收证据

环境：Ubuntu 24.04.5 aarch64 / NVIDIA GB10 / 驱动 580.178.04 / CUDA 13.0
Python：`prefix/pxdesign/venv`（独立 venv，Python 3.14.10，经 uv 创建，**不与 `prefix/protenix` 合并**）
PyTorch：2.14.1+cu130　LayerNorm：`LAYERNORM_TYPE=torch`（上游 fast_layernorm 在 sm_121 上无法编译，按上游文档回退）

## 验收用例

PDL1 quick start 完整 pipeline（扩散设计 → ProteinMPNN → AF2 过滤）。

- 作业目录：`prefix/pxdesign/jobs/run2`
- 开始：2026-11-11 20:28:40 +0800
- 结束：2026-11-11 20:30:07 +0800，`rc=0`
- 墙钟：86.66 s
- GPU 利用率峰值：96%（`prefix/pxdesign/jobs/run2/gpu.csv`，1s 采样）
- 无 ERR 产物

## 产出

- 结构预测：`out/global_run_0/PDL1_quick_start/seed_682563/predictions/PDL1_quick_start_sample_{0,1}.cif`
- 设计结果：`out/design_outputs/PDL1_quick_start/orig_designed/rank_{1,2}.cif`
- 通过过滤：`out/design_outputs/PDL1_quick_start/passing-AF2-IG-easy/rank_{1,2}.cif`
- 汇总：`out/design_outputs/PDL1_quick_start/summary.csv`

两条设计均 `AF2-IG-success=True`、`AF2-IG-easy-success=True`，af2_plddt 0.95，af2_ptm 0.86，af2_iptm 0.82。

## 对上游的处理方式

submodule 内容保持干净，Python 3.14 所需修正一律以外层 patch / 覆盖清单形式存放：

- `deps/pxdesign.txt`：依赖覆盖，逐条写明原因。
- `patches/pxdesign-argparse-percent.patch`
- `patches/pxdbench-json-float.patch`

AF2 权重：`prefix/pxdesign/tool_weights/af2/params_model_1.npz`（373,069,562 B）、`params_model_1_ptm.npz`（373,103,340 B），均已完整下载。

## 尚未验收

systemd 服务层（`systemctl --user start`）尚未验收，需用户同意安装 unit 后补充。
