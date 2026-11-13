# 第三阶段服务验收

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
- 无 MySQL 时服务受理失败，本机未启用真实 `cli_cfg.*.binary`，因此没有端到端 HTTP→GPU 推理证据。
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
