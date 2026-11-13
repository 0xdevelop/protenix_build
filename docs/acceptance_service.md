# 第三阶段服务验收

## gRPC APIService.Call 门禁验收（2026-11-14 03:01 Asia/Singapore）

在不改服务代码、不改 `build_srcs`、不改三仓、不装 MySQL、不改 Task 契约、不跑 GPU、不把邮件密钥写入仓库的前提下，临时把忽略文件 `example_files/config_local.yaml` 的 `auth_cfg.enabled` 设为 `true`，SQLite 改到隔离库 `./tmp/grpc-call-accept/protenix_service.db`，复用第七轮已构建的 `protenix_service` 二进制（2026-11-14 01:56，未重建），以 Debug 模式短时启动服务（`127.0.0.1:18001`–`18006`）。用仓库外的一次性 Go 客户端（`APIService` 已生成 stub：`github.com/0xdevelop/protenix_service/api/api_grpc/protobuf`）对 `127.0.0.1:18005` 实际调用 `APIService.Call`。本机无 `grpcurl`，未安装系统包，也未启用 systemd。验完已恢复原配置（`enabled: false`、原库路径，sha256 与改前一致），未留下进程、监听端口或含密钥的备份。桌面 Cursor worker 仍挂在既有仓库，不是本切片。

gRPC 元数据键使用 `authorization`（小写；gRPC/HTTP2 元数据键大小写不敏感，服务端 `grpcIncomingMetadata(ctx, "authorization")` 读取后交给 `WithBearerToken`，载荷与 HTTP `Authorization` 头相同，值为 `Bearer …` 或空）。`CallRequest.method` 为 `tools/call`，业务方法名在 `params.name`。

原始记录：`tmp/handoff-followup/phase3-service/grpc-call/`（结果已脱敏，不含密钥；一次性客户端与脚本也不进仓）。

### 同进程核对

| 检查 | 结果 |
| --- | --- |
| 监听 | `127.0.0.1:18001`–`18006` 均在听；gRPC 约 0.6s 后就绪 |
| JSON-RPC `POST http://127.0.0.1:18001/` Public `test` | HTTP 200，`isError=false`，`this is test method, request is success`（14ms）。与第七轮同一套临时门禁配置 |

### gRPC `APIService.Call`（`127.0.0.1:18005`，明文）

传输层均成功（gRPC status OK）；业务结果在统一 `CallToolResult` 里（`isError` / `error_code`）。受保护方法耗时约 1ms，服务日志只见方法名，无 `Execute` / `cli_proc` / `storage_mysql is not enabled` / `protenix-run`，未进入 Execute。

| 调用 | 结果 |
| --- | --- |
| Public `test`，无凭证 | `isError=false`，`this is test method, request is success` |
| Public `test`，伪造 JWT `authorization: Bearer …` | 同样成功；Public 方法不因假凭证失败 |
| Public `test`，伪造 `ptxk_` Bearer | 同样成功 |
| 受保护 `protenix` / `pxdesign` / `task.list` / `auth.jwt_token.check`，无凭证 | `error_code=10004` `permission denied`，未进入 Execute |
| 上述四个受保护方法，伪造 JWT 或伪造 `ptxk_` | 均为 `10004` `permission denied`，未进入 Execute |

### 仍然有效的边界

- 真实注册/登录仍缺 Resend 的 `email.api_key` 与 `from`。本机常驻 `config_local.yaml` 因此保持 `auth_cfg.enabled=false`。没有签发真实 `ptxk_`，也没有成功的登录 session。
- 无 MySQL 时，即使通过门禁，HTTP 异步受理仍不会进入 `Execute`。
- `task.cancel` 仍只取消 queued。未改模板 Task 契约，未装 MySQL，未跑 GPU。
- 本切片只补第七轮留下的 gRPC `Call` 缺口，不是第四阶段，也不宣称生产级认证或全部安全。

---

## auth 门禁启用后的注册/登录路径（2026-11-14 01:56–01:57 Asia/Singapore）

在不改 `build_srcs`、不改三仓、不装 MySQL、不改 Task 契约、不跑 GPU、不把邮件密钥写入仓库的前提下，临时把忽略文件 `example_files/config_local.yaml` 的 `auth_cfg.enabled` 设为 `true`，SQLite 改到隔离库 `./tmp/auth-login-accept/protenix_service.db`，以 Debug 模式短时启动服务（`127.0.0.1:18001`–`18006`），验证门禁与注册/登录前置路径。验完已恢复原配置（`enabled: false`、原库路径），未留下进程或监听端口，未 enable systemd。桌面 Cursor worker 仍挂在既有仓库，不是本切片。

本机该文件的 `auth_cfg.email.api_key` 与 `from` 均为空；邮件通道当前只支持 `resend`。因此不能完成真实发码、注册、登录后再调受保护方法。没有伪造邮件供应商，也没有为此改模板契约。

原始记录：`tmp/handoff-followup/phase3-service/auth-login/`（结果已脱敏，不含密钥）。

### 构建与单元测试

| 检查 | 结果 |
| --- | --- |
| `go test ./api/api_auth/... ./ability/ability_user ./config` | 退出码 0；`api_auth_api_key` 1.384s、`api_auth_bridge` 0.008s、`config` 0.020s；其余子包无测试文件 |
| `go build -o protenix_service .` | 退出码 0，约 4.4s |

### JSON-RPC（`POST http://127.0.0.1:18001/`）

下列调用的 HTTP 状态均为 200，业务结果在统一 `CallToolResult` 里（`isError` / `error_code`）。

| 调用 | 结果 |
| --- | --- |
| Public `test`，无凭证 | `isError=false`，`this is test method, request is success`（14ms） |
| Public `test`，携带伪造 `Authorization: Bearer` | 同样成功；Public 方法不因假凭证失败 |
| 受保护 `protenix` / `pxdesign` / `task.list` / `auth.jwt_token.check`，无凭证 | `error_code=10004` `permission denied`，未进入异步受理或 Execute |
| 受保护 `protenix`，伪造 JWT 或伪造 `ptxk_` | 均为 `10004` `permission denied` |
| Public `auth.verify_code.send.email`（`auth-accept@example.invalid`） | `error_code=10005` `verification code delivery failed`。服务日志：`auth_cfg.email.api_key is empty`，随后 `auth operation failed: load email config`。响应不回传缺键细节 |
| Public `auth.register`（虚构验证码 `000000`） | `error_code=10003` `invalid arguments` |
| Public `auth.login.email`（未知邮箱+密码） | `error_code=10004` `permission denied`，未暴露账户是否存在 |
| `name=/v1/protenix` | `error_code=10001` `method not found` |

### 其他协议

| 检查 | 结果 |
| --- | --- |
| MCP `POST http://127.0.0.1:18002/`（不是 `/mcp`），带 `Mcp-Protocol-Version: 2026-07-28` 等握手后请求头 | Public `test` 成功；`protenix` 无凭证返回 `10004`。此前误打 `POST /mcp` 得到空 body，不能当作验收 |
| WebSocket `ws://127.0.0.1:18004/`，`Origin: http://127.0.0.1:18004` | 握手 101，Public `test` 成功 |
| 同一 WebSocket，`Origin: http://127.0.0.1`（无端口） | 握手 403；日志：`Origin "127.0.0.1" is not authorized for Host "127.0.0.1:18004"`。配置允许 `127.0.0.1:*` / `localhost:*`，无端口的 Origin 不匹配 |
| test_ui `GET http://127.0.0.1:18003/` | HTTP 200，`text/html` |
| frontend `GET http://127.0.0.1:18006/` | HTTP 200，`text/html` |
| gRPC `127.0.0.1:18005` | 端口在听；本机无 `grpcurl`，未做 `APIService.Call` 实测 |

test_ui / frontend 本切片只验页面可打开，没有通过页面完成一次带登录的真实方法调用。这不是第四阶段交付。

### 仍然有效的边界

- 真实注册/登录仍缺 Resend 的 `email.api_key` 与 `from`。本机常驻 `config_local.yaml` 因此保持 `auth_cfg.enabled=false`，以免在无邮件配置时让后续未认证探测误判。
- 无 MySQL 时，即使通过门禁，HTTP 异步受理仍不会进入 `Execute`。
- 没有签发真实 `ptxk_` API key，也没有成功的登录 session。不宣称生产级认证或全部安全。
- 未改模板 Task 契约，未装 MySQL，未跑 GPU。

---


## 官方 CLI 经 Execute 的短命令与故障输入（2026-11-14 00:55–00:57 Asia/Singapore）

在不改 `build_srcs`、不改三仓与仓库 `prefix/`、不装 MySQL、不改 Task 契约、不跑 GPU 长预测的前提下，用 7d208af 干净发布包在临时前缀安装官方包装命令，并把 `cli_cfg.*.binary` 指到真实 `protenix-run` / `pxdesign-run`，直接调用 `Execute`。未改本机 `config_local.yaml`，未启动 systemd。桌面 Cursor worker 仍挂在既有仓库，不是本切片。

发布包：`build/upload_tmp_dir/protenix_linux_arm64_release_v0.0.1.zip` 与同目录 `pxdesign_linux_arm64_release_v0.0.1.zip`（`BUILD_INFO.commit=7d208afe550972486b35985cb1de2a5377b85cf5`，`dirty=0`）。临时目录 `/home/certa/pkg_accept_cli`，`WEIGHTS_REUSE_FROM=/home/certa/workspace/protenix_build/prefix`。原始记录：`tmp/handoff-followup/phase3-service/official-cli-execute-result.txt`。开始时 GPU 利用率 0%，本机 ComfyUI 约 170MiB 驻留，未结束该进程。

### 安装与帮助

| 检查 | 结果 |
| --- | --- |
| Protenix 安装前 status | rc=1，未安装 |
| `PROTENIX_PREFIX=... WEIGHTS_REUSE_FROM=... install_protenix.sh install` | rc=0，墙钟 49.094s；版本 `v0.0.1-7d208afe5509`，状态：可运行 |
| PXDesign 安装前 status | rc=1，未安装 |
| `PXDESIGN_PREFIX=... WEIGHTS_REUSE_FROM=... install_pxdesign.sh install` | rc=0，墙钟 38.969s；版本 `v0.0.1-7d208afe5509`，状态：可运行 |
| `protenix-run pred --help` | rc=0，1.648s，无 CIF |
| `pxdesign-run pipeline --help` | rc=0，0.065s，无 CIF |
| 仓库 `prefix/` 快照 | 安装、试跑前后一致 |
| `uninstall --purge` | 两个前缀 rc=0，临时目录已删 |

### 官方包装命令直接试跑

| 检查 | 退出码 | 墙钟 | CIF / ERR 文件 | 说明 |
| --- | --- | --- | --- | --- |
| Protenix 缺输入文件 | 1 | 1.619s | 0 / 0 | 不是 CLI 参数校验失败；日志写了 infer 启动后报 `Can not read a special file` |
| PXDesign 缺输入文件 | 2 | 0.039s | 0 / 0 | Click：`--input` 文件不存在 |
| Protenix 非法 JSON | 0 | 30.343s | 0 / 0 | 先初始化环境并加载 `protenix_base_default_v1.0.0.pt`，再报 JSON 解析失败。包装命令只在 `ERR/` 非空时改退出码为 3，本例仍为 0 |
| PXDesign 非法 YAML | 1 | 7.994s | 0 / 0 | `ValueError: Error parsing YAML file: mapping values are not allowed here` |
| 非法输入原文件 | — | — | — | 内容与 mtime 均未变 |

直接试跑结束后 GPU 利用率仍为 0%。非法 JSON 虽然不是长预测，但会加载权重，约 30s。

### 经 Execute 调用（不走 HTTP）

无 MySQL，HTTP 异步受理仍不会进入 `Execute`，本切片直接调 `Execute`。`version=v1` 只作方法参数。

| 检查 | 结果 |
| --- | --- |
| Protenix / PXDesign 缺必填 `input` | `Execute` 返回 `invalid arguments`，未启动进程（17ms / 3ms） |
| 输入路径不存在 | 启动进程前失败：`input path is not accessible`（0s） |
| Protenix 非法 JSON | argv 为 `protenix-run pred --input <隔离副本> --out_dir <作业 output/>`，**不含** `version`；墙钟 30.65s；`exit_code=0`，`cif_count=0`，`has_err=true`，`cancelled=false`；原文件未改 |
| PXDesign 非法 YAML | argv 为 `pxdesign-run pipeline --input <隔离副本> --dump_dir <作业 output/> --preset preview`；墙钟 3.27s；`exit_code=1`，`cif_count=0`，`has_err=false`；原文件未改 |

说明：`has_err=true` 只表示输出目录中存在名为 `ERR` 的目录，即使其中没有文件。官方包装命令只在 `ERR/` 非空时把退出码改为 3。本例 Protenix 非法 JSON 仍是退出码 0、无 CIF，必须同时看退出码、CIF、ERR 和运行日志。

探针里 `BuildArgvForTest` 与 `Execute` 会各自生成 task id，因此打印出的 argv 作业目录与 `payload.job_dir` 不是同一次调用；这不影响「version 不进 CLI」的结论。缺必填 `input` 时，`Execute` 先校验失败；探针额外调用的 `BuildArgvForTest` 不走该校验，空路径被解析为服务工作目录，并因拒绝拷贝 `logs/` 下符号链接而报错。这不是 HTTP 或 `Execute` 受理路径。

### 仍然有效的边界

- 无 MySQL 时 HTTP 异步受理仍为 `storage_mysql is not enabled`，没有端到端 HTTP→推理证据。
- 模板 `task.cancel` 仍只取消排队任务；执行中取消须另改契约，本切片不做。
- 本切片没有成功的结构预测或设计产物，不宣称生产级推理或全部安全。原生结果不能只看出时码。
- Protenix v2 缺授权权重，本地不能宣称 v2 跑通。

---

## CLI 接线与进程组取消（2026-11-13 23:56 Asia/Singapore）

在已提交的 `protenix_service` 骨架上接线命令组装与进程组跑步器。未改 `build_srcs`、未改三仓、未改模板 Task 契约、未安装 MySQL、未跑 GPU、未把本机 `config_local.yaml` 指向真实推理二进制。

原始测试输出：`tmp/handoff-followup/phase3-service/cli-proc-ability-test.log`、`config-test.log`。

### 方案与实现

- 新增 `cli_proc`：`Setpgid` 启动命令；context 取消时向整个进程组发 SIGTERM，超时后再发 SIGKILL。包装壳先退出而同组子进程仍在时，`Run` 会回收残留成员。
- 结构化配置 `cli_cfg`（`config/cli_config.go`，已写入 `example_files/config_example.yaml` 与 `generateDefaultConfig`）。`binary` 为空则 `Execute` 拒绝启动进程，不猜安装路径。
- `protenix` / `pxdesign` 的 `Execute` 按 CLI 长选项组装 argv；`version` 不进入命令行。输入拷贝到 `work_root/<task_id>/input/`，输出写到同任务 `output/`，原输入内容与 mtime 不变。
- 结果附带退出码、是否取消、`cif_count`、`has_err`。原生成功不能只看退出码。

### 实测（短命令，非 GPU）

| 检查 | 结果 |
| --- | --- |
| `go test ./cli_proc ./ability/ability_protenix ./ability/ability_pxdesign ./ability/ability_task ./config` | 退出码 0 |
| 取消整组 | `TestCancelSignalsWholeProcessGroup`：包装壳与子进程都退出 |
| 只向包装壳发 SIGTERM | `TestSignalWrapperOnlyLeavesChildRunning`：子进程仍在，复现此前 PXDesign 取消边界 |
| 包装壳被杀后由 Run 回收 | `TestRunReapsLeftoversWhenWrapperDies`：残留子进程被回收 |
| 输入隔离 | `TestStageInputCopiesAndLeavesOriginalUnchanged`、`TestBuildArgvOmitsVersionAndStagesInput` |
| 未配置 binary | `Execute` 返回 `CLI binary is not configured` |
| 配置占位脚本 | dummy `Execute` 退出码 0，并能报告 CIF；context 取消时进程停止 |
| 无 MySQL 的异步受理 | 仍为 `storage_mysql is not enabled`，HTTP 路径不会进入 Execute |
| `go build -o protenix_service .` | 退出码 0 |

### 仍然有效的边界

- 模板 `task.cancel` 只取消 `queued` 任务，执行中任务不可取消。Worker 对已认领任务使用 `context.WithoutCancel`。要把进程组取消接到 `task.cancel` 或停机信号，需要另行决定并改契约，本切片不做。
- 无 MySQL 时服务受理失败，因此没有端到端 HTTP→推理证据。真实 `cli_cfg.*.binary` 的短命令与故障输入见上文 2026-11-14 切片。
- 不宣称生产级取消或全部安全。

---

# 第三阶段服务骨架验收（本切片）

记录时间：2026-11-13 23:03 Asia/Singapore (UTC+8)  
机器：spark-901f  
基于父仓 `7d208afe550972486b35985cb1de2a5377b85cf5` 新增本目录与文档  
模板仓：`/home/certa/workspace/project_template_go` 停在 `ebef2c695bf1d4667a92b54100f9f158bda6ce0d`，工作区干净，前缀仍为 `key_`。  
本切片未改 `build_srcs`、未改三仓、未跑 GPU、未安装 MySQL。

原始命令输出在被忽略目录：`tmp/handoff-followup/phase3-service/`。

## 实例化

- 禁止从 GitHub `main` 浅克隆。将模板 `new_project.sh` 复制到 `tmp/handoff-followup/phase3-service/new_project_local.sh`，改为从本地模板仓按钉定提交复制。
- 在空目录 `/home/certa/workspace/protenix_build/protenix_service/` 执行（事先不放 LICENSE/README，避免脚本误用父仓文件）：

```bash
bash tmp/handoff-followup/phase3-service/new_project_local.sh github.com/0xdevelop/protenix_service ptxk_
```

- 退出码 0。独立 module：`github.com/0xdevelop/protenix_service`。`APIKeyPrefix = "ptxk_"`。服务目录无第二份 LICENSE。实例化后模板仓仍干净、仍为 `key_`。
- 工具链：`GOTOOLCHAIN=auto`，入口 `/home/certa/workspace/_gotoolchain_go125/go/bin/go`（1.25.3，按 go.mod 拉 1.26.10）；`protoc` 与插件复用模板仓 `tmp/handoff-acceptance/tools/`，未新装系统包。

## 构建

在 `protenix_service/` 内：

- `./gen_proto.sh` 退出码 0
- `./gen_frontend.sh` 退出码 0（官方脚本 + 本机 Bun 1.4.4）
- `./gen_test_ui.sh` 退出码 0
- `./gen_api_docs.sh` 退出码 0，写出 21 个方法；`docs/api_methods.md` 含 `# 7. protenix`、`# 8. pxdesign`，版本/模型/preset/输入输出在 arguments / InputSchema，没有 `/v1/protenix` 这类路径
- `go build -o protenix_service .` 退出码 0，二进制 `/home/certa/workspace/protenix_build/protenix_service/protenix_service`（已忽略，不提交）

参数名对齐本机 CLI 帮助：`tmp/handoff-followup/phase3-service/protenix-pred-help.txt`（`LAYERNORM_TYPE=torch` 调用 prefix venv）、同目录 `pxdesign-pipeline-help.txt`。

## 测试

- `go test ./ability/ability_protenix ./ability/ability_task` 退出码 0。日志：`tmp/handoff-followup/phase3-service/go-test-ability.log`
- `protenix` / `pxdesign` 注册为受保护的 `Async: true` 方法。无 MySQL 时经 `APIExecuter` 受理失败，错误为 `storage_mysql is not enabled`（`tmp/handoff-followup/phase3-service/async-accept-error-print.log`）。任务不会写入 SQLite。
- Execute 在参数合法时返回「尚未接线到原生 CLI」，缺必填或非法 `version`/`preset` 时返回 invalid arguments。本切片未调用 `protenix-run pred` / `pxdesign-run pipeline`。

## systemd 与短时启停

- 用户单元：`protenix_service/example_files/protenix_service.service`（`Type=simple`，无 `User=root`，`WantedBy=default.target`，ExecStart/WorkingDirectory 指向本机工作副本）。
- `systemd-analyze --user verify example_files/protenix_service.service` 退出码 0。
- 验收时把单元临时放到 `~/.config/systemd/user/`，`systemctl --user start`（未 enable）。`systemctl --user is-enabled` 为 `disabled`。
- 启动后 127.0.0.1 监听：JSON-RPC `18001`、MCP `18002`、test_ui `18003`、WebSocket `18004`、gRPC `18005`、frontend `18006`。证据：`listen-ports.txt`、`systemd-status-start.txt`。
- 验完 `systemctl --user stop` 退出码 0，状态 `inactive`，上述端口已关闭；随后删除临时用户单元并 `daemon-reload`，`example_files` 中的单元保留。未留下 enabled 且失败的常驻服务。

本机验收 `config_local.yaml`（已忽略，不提交）把端口改为 `18001`–`18006`，API 与 test_ui/frontend 均绑定 `127.0.0.1`。为在无邮件注册的情况下探测 Async 受理，该本地文件将 `auth_cfg.enabled` 设为 `false`。可提交的 `config_example.yaml` 仍为默认端口与 `auth_cfg.enabled: true`。

## 协议探测（JSON-RPC `http://127.0.0.1:18001/`）

| 调用 | HTTP | 结果 |
| --- | --- | --- |
| Public 方法 `test` | 200 | `this is test method, request is success`（`rpc-test.txt`） |
| `protenix` / `pxdesign` 合法 arguments | 500 | JSON-RPC `-32603` `internal service error`（模板把非业务错误映射为通用内部错误，响应里不回传底层文案） |
| `name: "/v1/protenix"` | 200 | `error_code` 10001 `method not found` |

底层明确错误由同进程的 `APIExecuter` 实测得到：`storage_mysql is not enabled`。服务日志只记录 `API method=[protenix]` 等，不打印该底层文案。这是模板契约，本切片未改受理或 Adapter。

## 边界

- 存储默认只开 SQLite；Auth/User 走主库 SQLite。Async/Task 固定走 `storage.MysqlDB`，未启用 MySQL 时受理失败，不把 Task 改造成 SQLite，也不安装 MySQL。
- 功能入口尚未接线到原生 CLI，不跑 GPU。
- 取消：本切片无生产级取消。若后续接线长任务，必须跟踪实际上游进程或进程组。
- `protenix_service/example_files/config_local.yaml`、`protenix_service/data/`、服务二进制已写入忽略规则，`git status` 不会把它们列为待提交文件。
