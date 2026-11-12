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

## 交付物

两个产物都是**命令行工具**（非常驻服务）。队列、并发、对外接口留给后续阶段。

- `./build.sh pack` 产出 zip：安装脚本（`install_<app>.sh` + `scripts/install_common.sh` + `install_prefix_*`）、命令入口 `bin/<app>-run`、配置模板 `conf/<app>.env`、**git archive 的上游快照**（`src/<product>/` + `src/SRC_SHA`）、`deps/`、`patches/`、`weights_reuse.sh`、`examples/`、`README.md`、`BUILD_INFO.txt`
- 包内安装只读包内路径；联网仅用于 pip 与权重
- 仓库内 `./build.sh protenix|pxdesign` 通过 `scripts/repo_src_defaults.sh` 指向 submodule（该文件不打进 zip）

## 安装布局（`install_<app>.sh`）

- 安装目录默认 `~/.local/share/<app>`（`<APP>_PREFIX` 覆盖），不需要 sudo
- `releases/<版本>/` 每版一套 venv；`current` / `previous` 符号链接，`update` 先构建新版本、校验通过再原子切换，失败不动旧版本；`rollback` 切回 `previous`
- `conf/`（配置）、`data/`（权重）在 `update` 时保留；`uninstall` 默认保留、`--purge` 才删

## 验收分层

脚本可跑、zip 生成、`<app>-run ... --help`、GPU 真推理（有 CIF、无 ERR/、GPU util>0）是不同层级，不可互相替代。

<!-- acceptance rerun marker -->
