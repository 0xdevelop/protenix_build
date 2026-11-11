# protenix_build

跨平台包装构建仓：submodule 接入上游，本机/服务器**原生安装** + **systemd system 服务**交付（**不以 Docker 为主路径**）。

## 架构硬约束（用户口径，勿改写）

| 项 | 约定 |
|----|------|
| 目标运行栈 | **CUDA 13**、**Python 3.14**、**Node 24 LTS** |
| 交付形态 | 原生安装 + systemd system 服务（可观测底层进程、系统级可控） |
| Docker | 尽可能不用；docker-compose / Dockerfile 不作为主路径 |
| 语言分工 | 仅 `protenix` / `pxdesign` 依赖 Python；本仓编排尽量 **Go + shell**，不引入 Python 构建编排堆 |
| 源码 | `build_srcs/*` 为 submodule；不改 submodule 内代码；`build_srcs/` 进 `.gitignore` |

> 上游官方 pin（如 pxdesign 侧旧 torch / 旧 Python）与上表冲突时，**以上表为目标**；收敛方案由下一阶段落地，不得把旧 pin 写成永久架构。

## Submodule

```bash
git submodule update --init --recursive
```

- `build_srcs/protenix` → `git@github.com:bytedance/Protenix.git`
- `build_srcs/pxdesign` → `git@github.com:bytedance/PXDesign.git`

## 双环境策略（prefix 隔离）

| 产品 | prefix | 策略 |
|------|--------|------|
| protenix | `prefix/protenix` | 跟最新 `build_srcs/protenix` submodule |
| pxdesign | `prefix/pxdesign` | 独立 prefix，不与最新 submodule 工作树混装 |

目标栈仍是 CUDA 13 / Python 3.14 / Node 24 LTS；当前模板里若仍残留上游 torch 版本提示，视为**待收敛债务**，不是对硬约束的覆写。

## 服务形态

- **冒烟 unit**（`protenix.service` / `pxdesign.service`）：`Type=oneshot`，主进程 Go `protenixd` / `pxdesignd` 预检 CLI 后退出；环境缺失即 failed。
- **批作业**（`*-oneshot.service`）：`Type=oneshot`，`protenixd pred -n ${PROTENIX_MODEL} ...`，退出码透传，`journalctl -u` 可查。
- 上游没有常驻服务入口，**不交付 Type=simple 常驻 unit**。
- 模型版本单一切换点：`conf/protenix.env` 的 `PROTENIX_MODEL`（默认 v1；v2 需授权权重）。
- 验收记录：`docs/acceptance_protenix_gb10.md`。

## gen / build（双 arch）

```bash
chmod a+x gen_pre_build_config.sh build.sh
./gen_pre_build_config.sh all
./gen_pre_build_config.sh validate gen_pre_build_config_linux_amd64.yaml
./gen_pre_build_config.sh validate gen_pre_build_config_linux_arm64.yaml

bash build.sh release linux_amd64
bash build.sh release linux_arm64
```

产物：`build/upload_tmp_dir/{protenix,pxdesign}_linux_{amd64|arm64}_release_v*.zip`

## 目标机装 prefix

```bash
bash scripts/install_prefix_protenix.sh
bash scripts/install_prefix_pxdesign.sh
```

然后解压 zip，`INSTALL_SYSTEMD=1 bash install_*.sh`。

## 发版边界

本阶段**不发版、不 push**（除非用户当次明确要求）。不要把 `git_tag.sh` / release workflow 当默认主路径。
