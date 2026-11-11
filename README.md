# protenix_build

跨平台包装构建仓：submodule 接入上游，产出 **zip + systemd** 可安装包（主路径非 Docker）。

## Submodule

```bash
git submodule update --init --recursive
```

- `build_srcs/protenix` → bytedance/Protenix（**禁止改内文件**）
- `build_srcs/pxdesign` → bytedance/PXDesign（**禁止改内文件**）

## 双环境策略

| 产品 | prefix | 策略 |
|------|--------|------|
| protenix | `prefix/protenix` | 最新 submodule，torch 2.7.1 链；产品 Python **3.11–3.12**（可到 3.13），禁 3.14 |
| pxdesign | `prefix/pxdesign` | 钉死 Protenix `v0.5.0+pxd` + torch `2.3.1`；**不要**用最新 submodule 填此 env |

宿主锚点：CUDA **13** / 可有 Python 3.14 / Node 24 LTS（Node 不参与本链）。prefix 内装 cu12 torch wheel。

## 服务形态

- **主 unit**（`*.service`）：Go supervisor `protenixd` / `pxdesignd`，`Type=simple`，可 `systemctl status`
- **批作业**（`*-oneshot.service`）：`Type=oneshot` + `*-run` 调上游 CLI
- 不是伪装 HTTP；上游本身是批处理 CLI

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
bash scripts/install_prefix_protenix.sh   # 无 /dev/nvidia* 默认 SKIP，写 tmp/*.skip
bash scripts/install_prefix_pxdesign.sh
# 强制装：SKIP_IF_NO_GPU=0 bash scripts/install_prefix_*.sh
```

然后解压 zip，`INSTALL_SYSTEMD=1 bash install_*.sh`。

验证：

```bash
/opt/protenix_build/prefix/protenix/bin/protenix-run --help
systemctl start protenix-oneshot.service
systemctl status protenix.service   # simple supervisor
```

## 发版边界

只用 `build.sh`。**不要**跑 `git_tag.sh`、打 release tag、触发 `.github/workflows/release.yml`（占位三段式）。
