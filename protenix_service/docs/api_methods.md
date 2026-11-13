> 本文件由 `gen_api_docs.sh` 从方法注册表生成（v0.0.1，共 21 个方法），禁止手改；新增方法后重新执行生成。

# 1. 统一调用方式

所有方法经同一入口调用，JSON-RPC over HTTP、MCP、WebSocket、gRPC 只是外壳不同，
运输同一份请求和同一份结果。业务方法由 `params.name` 选择，业务入参放在
`params.arguments`：

```json
{
  "jsonrpc": "2.0",
  "id": "request-id",
  "method": "tools/call",
  "params": {
    "name": "auth.login.email",
    "arguments": {
      "login_method": "password",
      "email": "user@example.com",
      "password": "password"
    }
  }
}
```

统一返回 MCP `CallToolResult`：成功 `isError=false`，`content[0].text`
直接承载业务 JSON；业务失败（含未注册方法、参数不合法、鉴权失败）HTTP 状态仍为
200，`isError=true`，`content[0].text` 为
`{"error_code":...,"error_msg":"..."}`。

**凭证怎么带**：除 Public 方法（`test`、验证码、注册、登录、refresh）外，每个方法都经统一
准入门禁。HTTP 使用 `Authorization: Bearer <凭证>` 头，gRPC 使用 `authorization` metadata，
WebSocket 可在握手请求头中携带。一次调用只带一种凭证。`auth_type` 一次只开一种。
`jwt` 时，`ptxk_` 前缀单独校验 API key（sha256 查库、对上用户、未吊销，不是 JWT 校验），其余校验自签 JWT 与未撤销 session；两边通过后才加载同一个 DB 用户。身份是 UserID，`api_key_id` 只是 key 行句柄。
`bridge` 时校验外部 IdP 令牌（本地公钥验签），身份是 claims，没有本地用户行；不接受本地 API key，也没有拿外部系统的 api key 在本地当凭证的入口。
JSON-RPC、WebSocket、gRPC 也可显式使用兼容字段 `arguments.jwt_token`（优先于头，门禁验证后移除，业务方法不可见；字段名不表示 API key 走 JWT 校验）。
浏览器原生 WebSocket 无法自行设置 Authorization 头，使用该兼容字段。
MCP 凭证使用 HTTP 头，`tools/list` 只暴露业务入参，不含 `jwt_token`。

**方法节怎么读**：每个方法节给出方法语义、`arguments` **传参举例**（必填字段的
实际请求形态，占位值按真实值替换）与 `arguments` **JSON Schema**（机器可校验的
约束说明——`required` 数组表示「哪些字段必填」，`properties` 内是各字段
类型与长度约束；**schema 本身不是请求体的一部分，不要照抄进请求**）。

# 2. 业务错误码

| error_code | error_msg |
| ---------- | --------- |
| 0 | 成功 |
| 10001 | method not found |
| 10002 | method is not supported |
| 10003 | invalid arguments |
| 10004 | permission denied |
| 10005 | verification code delivery failed |

# 3. test

检查统一 API 调用链是否可用

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "type": "object"
}
```

# 4. Auth

## 4.1. auth.verify_code.send.email

发送邮箱验证码

`arguments` 传参举例（仅含必填字段）：

```json
{
  "email": "<email>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "email": {
      "format": "email",
      "maxLength": 320,
      "minLength": 3,
      "type": "string"
    }
  },
  "required": [
    "email"
  ],
  "type": "object"
}
```

## 4.2. auth.verify_code.check.email

检查邮箱验证码

`arguments` 传参举例（仅含必填字段）：

```json
{
  "email": "<email>",
  "verify_code": "<verify_code>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "email": {
      "format": "email",
      "maxLength": 320,
      "minLength": 3,
      "type": "string"
    },
    "verify_code": {
      "pattern": "^[0-9]{6}$",
      "type": "string"
    }
  },
  "required": [
    "email",
    "verify_code"
  ],
  "type": "object"
}
```

## 4.3. auth.verify_code.send.sms

发送短信验证码（暂不支持）

`arguments` 传参举例（仅含必填字段）：

```json
{
  "phone": "<phone>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "phone": {
      "pattern": "^\\+[1-9][0-9]{7,14}$",
      "type": "string"
    }
  },
  "required": [
    "phone"
  ],
  "type": "object"
}
```

## 4.4. auth.verify_code.check.sms

检查短信验证码（暂不支持）

`arguments` 传参举例（仅含必填字段）：

```json
{
  "phone": "<phone>",
  "verify_code": "<verify_code>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "phone": {
      "pattern": "^\\+[1-9][0-9]{7,14}$",
      "type": "string"
    },
    "verify_code": {
      "pattern": "^[0-9]{6}$",
      "type": "string"
    }
  },
  "required": [
    "phone",
    "verify_code"
  ],
  "type": "object"
}
```

## 4.5. auth.register

使用邮箱验证码注册账户；user_name 为注册必填主标识

`arguments` 传参举例（仅含必填字段）：

```json
{
  "email": "<email>",
  "password": "<password>",
  "user_name": "<user_name>",
  "verify_code": "<verify_code>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "email": {
      "format": "email",
      "maxLength": 320,
      "minLength": 3,
      "type": "string"
    },
    "password": {
      "maxLength": 128,
      "minLength": 15,
      "type": "string"
    },
    "user_name": {
      "maxLength": 32,
      "minLength": 3,
      "type": "string"
    },
    "verify_code": {
      "pattern": "^[0-9]{6}$",
      "type": "string"
    }
  },
  "required": [
    "user_name",
    "email",
    "password",
    "verify_code"
  ],
  "type": "object"
}
```

## 4.6. auth.login.email

使用邮箱登录

`arguments` 传参举例（仅含必填字段）：

```json
{
  "email": "<email>",
  "login_method": "password",
  "password": "<password>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "email": {
      "format": "email",
      "maxLength": 320,
      "minLength": 3,
      "type": "string"
    },
    "login_method": {
      "enum": [
        "password"
      ],
      "type": "string"
    },
    "password": {
      "maxLength": 128,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "login_method",
    "email",
    "password"
  ],
  "type": "object"
}
```

## 4.7. auth.login.phone

使用手机号登录

`arguments` 传参举例（仅含必填字段）：

```json
{
  "login_method": "password",
  "phone": "<phone>"
}
```

可选字段：`password`、`verify_code`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "login_method": {
      "enum": [
        "password",
        "verify_code"
      ],
      "type": "string"
    },
    "password": {
      "maxLength": 128,
      "minLength": 1,
      "type": "string"
    },
    "phone": {
      "pattern": "^\\+[1-9][0-9]{7,14}$",
      "type": "string"
    },
    "verify_code": {
      "pattern": "^[0-9]{6}$",
      "type": "string"
    }
  },
  "required": [
    "login_method",
    "phone"
  ],
  "type": "object"
}
```

## 4.8. auth.logout

撤销当前登录状态

`arguments` 传参举例（仅含必填字段）：

```json
{}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "type": "object"
}
```

## 4.9. auth.jwt_token.check

按凭证种类分别检查当前自签 JWT 或 API key，返回用户身份与凭证来源；api_key_id 只是 key 行句柄

`arguments` 传参举例（仅含必填字段）：

```json
{}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "type": "object"
}
```

## 4.10. auth.jwt_token.refresh

轮换 refresh token 并签发新 JWT token

`arguments` 传参举例（仅含必填字段）：

```json
{
  "refresh_token": "<refresh_token>"
}
```

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "refresh_token": {
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "refresh_token"
  ],
  "type": "object"
}
```

## 4.11. auth.api_key.issue

签发当前用户的 API key，明文只返回一次；仅登录 session 可签发，key 不能再签发。

`arguments` 传参举例（仅含必填字段）：

```json
{
  "name": "<name>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "name": {
      "maxLength": 64,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "name"
  ],
  "type": "object"
}
```

## 4.12. auth.api_key.list

列出当前用户的 API key，不含明文与哈希；时间字段为 UTC 毫秒字符串。

`arguments` 传参举例（仅含必填字段）：

```json
{}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "type": "object"
}
```

## 4.13. auth.api_key.revoke

吊销一把 API key；仅登录 session 可吊销，且只能吊销自己的 key。

`arguments` 传参举例（仅含必填字段）：

```json
{
  "api_key_id": "<api_key_id>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "api_key_id": {
      "format": "uuid",
      "maxLength": 36,
      "minLength": 36,
      "type": "string"
    },
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "api_key_id"
  ],
  "type": "object"
}
```

## 4.14. auth.api_key.delete

删除一把已吊销的 API key；未吊销拒绝删除。仅登录 session 可删自己的 key。

`arguments` 传参举例（仅含必填字段）：

```json
{
  "api_key_id": "<api_key_id>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "api_key_id": {
      "format": "uuid",
      "maxLength": 36,
      "minLength": 36,
      "type": "string"
    },
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "api_key_id"
  ],
  "type": "object"
}
```

# 5. User

## 5.1. user.nickname.change

修改当前用户昵称

`arguments` 传参举例（仅含必填字段）：

```json
{
  "nick_name": "<nick_name>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "nick_name": {
      "maxLength": 32,
      "minLength": 1,
      "type": "string"
    }
  },
  "required": [
    "nick_name"
  ],
  "type": "object"
}
```

# 6. Task

## 6.1. task.get

查询我的异步任务状态与结果

`arguments` 传参举例（仅含必填字段）：

```json
{
  "task_id": "<task_id>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "task_id": {
      "maxLength": 36,
      "minLength": 36,
      "type": "string"
    }
  },
  "required": [
    "task_id"
  ],
  "type": "object"
}
```

## 6.2. task.list

列出我的异步任务（新→旧，最多 50 条）

`arguments` 传参举例（仅含必填字段）：

```json
{}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    }
  },
  "type": "object"
}
```

## 6.3. task.cancel

取消我的排队中任务（执行中任务不可取消）

`arguments` 传参举例（仅含必填字段）：

```json
{
  "task_id": "<task_id>"
}
```

可选字段：`jwt_token`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "task_id": {
      "maxLength": 36,
      "minLength": 36,
      "type": "string"
    }
  },
  "required": [
    "task_id"
  ],
  "type": "object"
}
```

# 7. protenix

提交 Protenix 结构预测任务（对应 CLI：protenix-run pred）。版本/模型走 arguments。异步队列固定走 MySQL，未启用时受理失败。未配置 cli_cfg.protenix.binary 时 Execute 拒绝启动进程。

异步方法：受理后返回 `task_id`，进度与结果经任务查询方法读取。

`arguments` 传参举例（仅含必填字段）：

```json
{
  "input": "<input>",
  "out_dir": "<out_dir>"
}
```

可选字段：`cycle`、`dtype`、`jwt_token`、`model_name`、`sample`、`seeds`、`step`、`use_default_params`、`use_msa`、`version`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "cycle": {
      "description": "Pairformer cycle 数。对应 CLI -c/--cycle。",
      "type": "integer"
    },
    "dtype": {
      "description": "推理 dtype。对应 CLI -d/--dtype。",
      "enum": [
        "bf16",
        "fp32"
      ],
      "type": "string"
    },
    "input": {
      "description": "输入 JSON 文件或目录。对应 CLI -i/--input。",
      "maxLength": 4096,
      "minLength": 1,
      "type": "string"
    },
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "model_name": {
      "description": "模型检查点名。对应 CLI -n/--model_name，例如 protenix_base_default_v1.0.0。",
      "maxLength": 256,
      "minLength": 1,
      "type": "string"
    },
    "out_dir": {
      "description": "调用方给出的结果目录名；实际写入隔离作业目录下的 output/，不直接改原输入。对应 CLI -o/--out_dir。",
      "maxLength": 4096,
      "minLength": 1,
      "type": "string"
    },
    "sample": {
      "description": "样本数。对应 CLI -e/--sample。",
      "type": "integer"
    },
    "seeds": {
      "description": "逗号分隔随机种子。对应 CLI -s/--seeds。",
      "maxLength": 256,
      "minLength": 1,
      "type": "string"
    },
    "step": {
      "description": "扩散步数。对应 CLI -p/--step。",
      "type": "integer"
    },
    "use_default_params": {
      "description": "是否使用模型推荐默认参数。对应 CLI --use_default_params。",
      "type": "boolean"
    },
    "use_msa": {
      "description": "是否使用 MSA。对应 CLI --use_msa。",
      "type": "boolean"
    },
    "version": {
      "description": "产品版本（v1/v2），不是 URL 路径。缺省 v1。v2 需要授权权重。不作为 CLI 开关传入。",
      "enum": [
        "v1",
        "v2"
      ],
      "type": "string"
    }
  },
  "required": [
    "input",
    "out_dir"
  ],
  "type": "object"
}
```

# 8. pxdesign

提交 PXDesign 设计流水线任务（对应 CLI：pxdesign-run pipeline）。preset 走 arguments。异步队列固定走 MySQL，未启用时受理失败。未配置 cli_cfg.pxdesign.binary 时 Execute 拒绝启动进程。

异步方法：受理后返回 `task_id`，进度与结果经任务查询方法读取。

`arguments` 传参举例（仅含必填字段）：

```json
{
  "dump_dir": "<dump_dir>",
  "input": "<input>"
}
```

可选字段：`N_max_runs`、`N_sample`、`N_step`、`dtype`、`eta_max`、`eta_min`、`eta_type`、`jwt_token`、`preset`。

`arguments` JSON Schema（约束说明，非请求体；`required` 数组 = 必填字段清单）：

```json
{
  "additionalProperties": false,
  "properties": {
    "N_max_runs": {
      "description": "最大 design run 数。对应 CLI --N_max_runs。",
      "type": "integer"
    },
    "N_sample": {
      "description": "扩散样本数。对应 CLI --N_sample。",
      "type": "integer"
    },
    "N_step": {
      "description": "扩散步数。对应 CLI --N_step。",
      "type": "integer"
    },
    "dtype": {
      "description": "推理 dtype。对应 CLI --dtype。",
      "enum": [
        "fp32",
        "bf16"
      ],
      "type": "string"
    },
    "dump_dir": {
      "description": "调用方给出的结果目录名；实际写入隔离作业目录下的 output/。对应 CLI -o/--dump_dir。",
      "maxLength": 4096,
      "minLength": 1,
      "type": "string"
    },
    "eta_max": {
      "description": "eta 调度最大值。对应 CLI --eta_max。",
      "type": "number"
    },
    "eta_min": {
      "description": "eta 调度最小值。对应 CLI --eta_min。",
      "type": "number"
    },
    "eta_type": {
      "description": "eta 调度类型。对应 CLI --eta_type。",
      "maxLength": 64,
      "minLength": 1,
      "type": "string"
    },
    "input": {
      "description": "输入 YAML/JSON 文件。对应 CLI -i/--input。",
      "maxLength": 4096,
      "minLength": 1,
      "type": "string"
    },
    "jwt_token": {
      "description": "一次只带一种凭证：自签 JWT，或 ptxk_ 前缀 API key（校验不同）。已带 Authorization: Bearer 时省略；显式传入优先于头。",
      "maxLength": 8192,
      "minLength": 1,
      "type": "string"
    },
    "preset": {
      "description": "流水线预设。对应 CLI --preset。",
      "enum": [
        "preview",
        "extended",
        "custom"
      ],
      "type": "string"
    }
  },
  "required": [
    "input",
    "dump_dir"
  ],
  "type": "object"
}
```
