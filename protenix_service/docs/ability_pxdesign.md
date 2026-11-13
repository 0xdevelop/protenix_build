# pxdesign 功能入口

固定方法名：`pxdesign`（MCP `tools/call` 的 `name`，不是 URL 路径）。

对应命令行：`pxdesign-run pipeline`。arguments 与 CLI 长选项对齐：`input`、`dump_dir`（CLI `-o/--dump_dir`）、`preset`（`preview`/`extended`/`custom`）、`N_sample`、`N_step`、`N_max_runs`、`dtype`、`eta_max`、`eta_min`、`eta_type`。筛选器/preset 放在 arguments，不进入路径。

注册为 `Async: true`。受理走模板 `AcceptAsyncTask` → `storage.MysqlDB`。本阶段存储只开 SQLite、不安装 MySQL，因此受理失败，错误含 `storage_mysql is not enabled`，任务不会写入 SQLite，HTTP 调用不会进入 Execute。

`Execute` 会按 `cli_cfg.pxdesign.binary` 组装命令：把输入拷贝到 `work_root/<task_id>/input/`，输出写到同任务 `output/`，在新进程组中启动官方包装命令。`binary` 为空时返回 `pxdesign CLI binary is not configured`，不会猜路径，也不会启动进程。结果摘要包含退出码、是否取消、CIF 数量和是否存在 ERR 目录。

取消：必须跟踪实际上游进程组，不能只向包装子壳发 SIGTERM。`cli_proc` 已用短命令复现该边界，并在 `Run` 取消或包装壳异常退出时回收同组残留进程。模板 `task.cancel` 仍只取消排队任务，本切片不改该契约。验证不跑 GPU。

在 `ability/ability.go` 的 `LoadAbilityAPIMethods` 中显式加载，禁止 init/反射自动注册。
