# protenix 功能入口

固定方法名：`protenix`（MCP `tools/call` 的 `name`，不是 URL 路径）。

对应命令行：`protenix-run pred`。arguments 与 CLI 长选项对齐：`input`、`out_dir`、`model_name`、`seeds`、`cycle`、`step`、`sample`、`dtype`、`use_msa`、`use_default_params`。产品版本 `version`（`v1`/`v2`）也放在 arguments 中，不作为 CLI 开关、不进路径；v2 需要授权权重。

注册为 `Async: true`。受理走模板 `AcceptAsyncTask` → `storage.MysqlDB`。本阶段存储只开 SQLite、不安装 MySQL，因此受理失败，错误含 `storage_mysql is not enabled`，任务不会写入 SQLite，HTTP 调用不会进入 Execute。

`Execute` 会按 `cli_cfg.protenix.binary` 组装命令：把输入拷贝到 `work_root/<task_id>/input/`，输出写到同任务 `output/`，在新进程组中启动官方包装命令。`binary` 为空时返回 `protenix CLI binary is not configured`，不会猜路径，也不会启动进程。结果摘要包含退出码、是否取消、CIF 数量和是否存在 ERR 目录；原生预测是否成功不能只看退出码。

取消：`cli_proc.Run` 在 context 取消时向整个进程组发 SIGTERM，必要时再发 SIGKILL，并回收包装壳退出后仍留在同组的子进程。模板 `task.cancel` 仍只取消排队任务；Worker 对已认领任务使用 `context.WithoutCancel`。本切片不改该契约，因此服务路径还不能取消正在跑的推理。验证用短命令/占位脚本，不跑 GPU。

在 `ability/ability.go` 的 `LoadAbilityAPIMethods` 中显式加载，禁止 init/反射自动注册。
