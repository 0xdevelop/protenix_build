# protenix_service

Protenix / PXDesign 常驻服务骨架。module：`github.com/0xdevelop/protenix_service`。API key 前缀：`ptxk_`。嵌套在 `protenix_build` 仓库中，沿用父仓许可证，不另放 LICENSE。

本阶段只提供可启动的服务骨架和固定功能入口，不执行 GPU 推理，不安装 MySQL。

## 构建

在本目录执行（需 Go 1.26.10 工具链、`protoc`、Bun；`GOTOOLCHAIN=auto`）：

```bash
./gen_proto.sh
./gen_frontend.sh
./gen_test_ui.sh
go build -o protenix_service .
```

`build.sh` 会在编译前调用前端生成脚本；不要跳过 `gen_frontend.sh` / `gen_test_ui.sh`。

## 配置

- 示例（可提交、无真实密钥）：`example_files/config_example.yaml`
- 本机运行（不要提交）：把示例复制为 `example_files/config_local.yaml` 后按需修改
- Debug 启动读取 `./example_files/config_local.yaml`；工作目录必须是本目录
- 存储默认只开 SQLite（`storage_cfg.primary: sqlite`，mysql/postgres/redis 为 `enabled: false`）。Auth/User 走主库 SQLite。
- 模板契约：Async/Task 固定走 `storage.MysqlDB`。未启用 MySQL 时，异步受理返回明确错误（`storage_mysql is not enabled`），不会把任务改写到 SQLite，也不要为此安装 MySQL。
- `example_files/config_local.yaml` 与 `data/` 已加入忽略规则，不要提交密钥或 SQLite 数据文件。

默认端口（示例配置）：JSON-RPC `13001`、MCP `13002`、test_ui `13003`、WebSocket `13004`、gRPC `13005`、frontend `13006`。test_ui 与 frontend 默认只绑定 `127.0.0.1`。本机验收如需避开占用，可在 `config_local.yaml` 改为 `18001`–`18006`。

## 启动

```bash
./protenix_service
```

或使用用户级 systemd 单元（不要用系统级 root 单元）：

```bash
# 单元文件：example_files/protenix_service.service
# Type=simple，ExecStart / WorkingDirectory 指向本目录的二进制
systemd-analyze --user verify example_files/protenix_service.service
systemctl --user start protenix_service.service
# 停止：
systemctl --user stop protenix_service.service
```

不要留下 enabled 且失败的常驻服务。

## 功能入口

所有协议共用一个业务调用入口 `tools/call`，用 `params.name` 选择方法，不要做成 `/v1/protenix` 这类路径。

| name | 说明 | arguments（与原生 CLI 长选项对齐） |
| --- | --- | --- |
| `test` | Public，检查调用链 | 无业务参数 |
| `protenix` | 对应 `protenix-run pred`，Async | 必填 `input`、`out_dir`；可选 `version`（`v1`/`v2`）、`model_name`、`seeds`、`cycle`、`step`、`sample`、`dtype`、`use_msa`、`use_default_params` |
| `pxdesign` | 对应 `pxdesign-run pipeline`，Async | 必填 `input`、`dump_dir`；可选 `preset`（`preview`/`extended`/`custom`）、`N_sample`、`N_step`、`N_max_runs`、`dtype`、`eta_max`、`eta_min`、`eta_type` |

JSON-RPC 示例（Public `test`）：

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "test",
    "arguments": {}
  }
}
```

向 `http://127.0.0.1:<jsonrpc-port>/` 发 POST。方法清单见 `docs/api_methods.md`（由 `./gen_api_docs.sh` 生成，不要手改）。

当前 `protenix` / `pxdesign` 仅做参数校验与异步受理。受理在未启用 MySQL 时失败；即便以后启用队列，Execute 也会明确返回「尚未接线到原生 CLI」，不会调用 `protenix-run pred` 或 `pxdesign-run pipeline`。
