# protenix 功能入口

固定方法名：`protenix`（MCP `tools/call` 的 `name`，不是 URL 路径）。

对应命令行：`protenix-run pred`。arguments 与 CLI 长选项对齐：`input`、`out_dir`、`model_name`、`seeds`、`cycle`、`step`、`sample`、`dtype`、`use_msa`、`use_default_params`。产品版本 `version`（`v1`/`v2`）也放在 arguments 中；v2 需要授权权重，本服务不会因此改路径。

注册为 `Async: true`。受理走模板 `AcceptAsyncTask` → `storage.MysqlDB`。本阶段存储只开 SQLite、不安装 MySQL，因此受理失败，错误含 `storage_mysql is not enabled`，任务不会写入 SQLite。Execute 只做参数校验，并返回尚未接线到原生 CLI；本阶段不调用 GPU，不执行 `protenix-run pred`。

在 `ability/ability.go` 的 `LoadAbilityAPIMethods` 中显式加载，禁止 init/反射自动注册。
