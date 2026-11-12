# Protenix 在 GB10 上的验收记录（2026-11-11）

层级说明见 `.cursor/rules/boundaries.mdc` 第 2 节：脚本能跑 / zip 生成 / `--help` 冒烟 / `systemctl start` 真实进程 / GPU 真推理。
本记录覆盖 **脚本能跑、--help 冒烟、GPU 真推理** 三层；`systemctl start` 层**未验收**（规则禁止在本机安装 unit 或 systemctl start，只做了 `systemd-analyze verify`）。

## 环境
- aarch64，NVIDIA GB10（compute capability 12.1），驱动 580.178.04，CUDA 13.0（/usr/local/cuda-13.0）
- Python 3.14.10（uv 管理），venv：`prefix/protenix/venv`
- torch 2.14.1+cu130、torchvision 0.29.1+cu130、triton 3.8.0、cuequivariance-ops-torch-cu13 0.13.0、
  deepspeed 0.19.9、biotite 1.4.0（源码编译）、rdkit 2026.9.1；完整清单见安装后生成的 `prefix/protenix/conf/pip-freeze.txt`
- Protenix submodule `85767b8`（v2.0.0 之后），模型 `PROTENIX_MODEL=protenix_base_default_v1.0.0`
- `LAYERNORM_TYPE=torch`（上游 fast_layernorm 在 torch 2.14 下编译失败：上游固定 `-std=c++17`，torch 2.14 要求 C++20；且 gencode 不含 sm_121）

## 安装
```bash
PYPI_INDEX_URL=https://mirrors.aliyun.com/pypi/simple bash scripts/install_prefix_protenix.sh
# → [install_prefix_protenix] status=ok src_sha=85767b8... model=protenix_base_default_v1.0.0
PROTENIX_MODEL=protenix-v2 bash scripts/install_prefix_protenix.sh
# → FAIL: PROTENIX_MODEL=protenix-v2 需要授权权重，本地缺少 .../checkpoint/protenix-v2.pt ... ；exit=1
```

## 推理（上游官方示例 examples/input.json，单链蛋白 693 残基，无 MSA）
```bash
set -a; source prefix/protenix/conf/protenix.env; set +a
protenixd pred -i jobs/input.json -o jobs/run3/output -n ${PROTENIX_MODEL} --use_msa false -s 101
```
- 结果：rc=0，总墙钟 165.3 s（其中上游统计 `Seed 101 completed in 131.42s`，5 个 sample、200 步扩散、10 个 cycle、bf16）
- GPU：nvidia-smi 每 2 s 采样，最高 96% 利用率、最高 54.5 W；整段（含加载）平均约 70%
- 输出：`output/user_test/seed_101/predictions/user_test_sample_{0..4}.cif` + `user_test_summary_confidence_sample_{0..4}.json`，无 `ERR/` 目录
- 结构检查：sample_0 有 5370 个 ATOM、693 个 CA（= 序列长度），相邻 CA 平均距离 3.76 Å、无 3.4–4.2 Å 以外的异常；无 NaN
- 置信度：pLDDT 33.9、pTM 0.25（该示例序列大段无序且未用 MSA，低分符合预期，不代表环境问题）

## 踩过的坑（都已在 deps / patches / 安装脚本中修正）
1. biotite 1.8.0 → `BondList has no attribute '_bonds'`，**上游此时退出码仍为 0，只产出 ERR/**。验收必须检查 CIF，不能只看退出码。已钉回 1.4.0。
2. `cuequivariance-ops-torch-cu13` 未安装 → 三角注意力 ImportError（同样退出码 0）。原因：uv override 只能替换已有依赖、不能新增；安装脚本已显式安装。
3. fast_layernorm JIT 编译失败 → 上游文档回退 `LAYERNORM_TYPE=torch`。

## 未验收 / 待做
- `systemctl start protenix-oneshot.service` 层：需要用户允许安装 unit 后再验收。
- fast_layernorm 自定义内核（性能优化，非功能必需）：需要上游修复 C++20/sm_121 编译参数。
