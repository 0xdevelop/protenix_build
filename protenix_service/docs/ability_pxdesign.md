# pxdesign 功能入口

固定方法名：`pxdesign`（MCP `tools/call` 的 `name`，不是 URL 路径）。

对应命令行：`pxdesign-run pipeline`。arguments 与 CLI 长选项对齐：`input`、`dump_dir`（CLI `-o/--dump_dir`）、`preset`（`preview`/`extended`/`custom`）、`N_sample`、`N_step`、`N_max_runs`、`dtype`、`eta_max`、`eta_min`、`eta_type`。筛选器/preset 放在 arguments，不进入路径。

注册为 `Async: true`。受理走模板 `AcceptAsyncTask` → `storage.MysqlDB`。本阶段存储只开 SQLite、不安装 MySQL，因此受理失败，错误含 `storage_mysql is not enabled`，任务不会写入 SQLite。Execute 只做参数校验，并返回尚未接线到原生 CLI；本阶段不调用 GPU，不执行 `pxdesign-run pipeline`。

取消：本切片不实现生产级取消。若后续做取消，必须跟踪实际上游进程或进程组，不能只向包装子壳发 SIGTERM。

在 `ability/ability.go` 的 `LoadAbilityAPIMethods` 中显式加载，禁止 init/反射自动注册。
