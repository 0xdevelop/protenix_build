# 设计说明

面向维护者的实现口径（使用者请看仓库根 `README.md`）。

## 运行栈

- 宿主：CUDA 13、Python 3.14、Node 24 LTS（编排侧）
- torch：仅从 `https://download.pytorch.org/whl/cu130` 安装 cp314 轮子（当前验证 2.14.1+cu130）
- 不用 Docker / conda / micromamba；不用 Python 3.11 回退

## 源码与约束

- 上游在 `build_srcs/{protenix,pxdesign}` submodule；**不修改** submodule 内文件
- 上游 `requirements.txt` 钉位在 3.14/aarch64/cu130 上不可用时，用仓库外层 `deps/` 覆盖，并在文件内逐条写原因
- 运行期兼容补丁（如 argparse `%`、pxdbench json float32）只打在 prefix 内快照或 site-packages，不回写 submodule

## 双 prefix

- `prefix/protenix` 与 `prefix/pxdesign` 两套独立 venv，禁止合并
- pxdesign 链依赖官方钉死的 Protenix@v0.5.0+pxd（与 protenix prefix 的「最新 submodule」不是同一套）

## 发布包

- `./build.sh go` 产出 zip：Go supervisor、unit/env、**git archive 的上游快照**（`src/<product>/` + `src/SRC_SHA`）、对应 `deps/`、`patches/`、安装脚本与 `weights_reuse.sh`
- 包内安装只读包内路径；联网仅用于 pip 与权重
- 仓库内 `./build.sh protenix|pxdesign` 仍通过 `scripts/repo_src_defaults.sh` 指向 submodule（该文件不打进 zip）

## systemd

- 冒烟 / 批作业均为 `Type=oneshot`；CLI 缺失或预检失败必须非零退出，禁止空转常驻
- 本仓构建流程不向 `/etc/systemd/system` 安装 unit

## 验收分层

脚本可跑、zip 生成、`--help`、systemd 拉起真实工作、GPU 真推理（有 CIF、无 ERR/、GPU util>0）是不同层级，不可互相替代。
