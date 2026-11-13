// Package ability_protenix 注册固定功能入口 protenix（MCP tools/call 的 name）。
// 版本、模型、输入输出等一律放在 arguments，不进入 URL 或方法路径。
package ability_protenix

import (
	"context"
	"errors"

	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_common"
	"github.com/0xdevelop/protenix_service/api/api_error_code"
	"github.com/0xdevelop/protenix_service/api/api_supported_methods"
)

const MethodProtenix = "protenix"

var errNotWiredToCLI = errors.New("protenix is not yet wired to the native protenix-run CLI")

func LoadAPIMethods() {
	api_supported_methods.AddMethod(&api_supported_methods.SupportedMethod{
		Name:        MethodProtenix,
		Description: "提交 Protenix 结构预测任务（对应 CLI：protenix-run pred）。本切片尚未接线到原生 CLI；异步队列固定走 MySQL，未启用时受理失败。",
		Async:       true,
		InputSchema: api_auth_common.InputSchema(
			map[string]interface{}{
				"version":            schemaWithDesc(api_auth_common.EnumStringSchema("v1", "v2"), "产品版本（v1/v2），不是 URL 路径。缺省 v1。v2 需要授权权重。"),
				"input":              schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "输入 JSON 文件或目录。对应 CLI -i/--input。"),
				"out_dir":            schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "结果输出目录。对应 CLI -o/--out_dir。"),
				"model_name":         schemaWithDesc(api_auth_common.StringSchema("", 1, 256), "模型检查点名。对应 CLI -n/--model_name，例如 protenix_base_default_v1.0.0。"),
				"seeds":              schemaWithDesc(api_auth_common.StringSchema("", 1, 256), "逗号分隔随机种子。对应 CLI -s/--seeds。"),
				"cycle":              schemaWithDesc(integerSchema(), "Pairformer cycle 数。对应 CLI -c/--cycle。"),
				"step":               schemaWithDesc(integerSchema(), "扩散步数。对应 CLI -p/--step。"),
				"sample":             schemaWithDesc(integerSchema(), "样本数。对应 CLI -e/--sample。"),
				"dtype":              schemaWithDesc(api_auth_common.EnumStringSchema("bf16", "fp32"), "推理 dtype。对应 CLI -d/--dtype。"),
				"use_msa":            schemaWithDesc(booleanSchema(), "是否使用 MSA。对应 CLI --use_msa。"),
				"use_default_params": schemaWithDesc(booleanSchema(), "是否使用模型推荐默认参数。对应 CLI --use_default_params。"),
			},
			"input", "out_dir",
		),
		Execute: Execute,
	})
}

func Execute(_ context.Context, input interface{}) (interface{}, error) {
	if err := validateProtenixArgs(input); err != nil {
		return nil, err
	}
	return nil, errNotWiredToCLI
}

func validateProtenixArgs(input interface{}) error {
	params, ok := api_auth_common.InputObject(input)
	if !ok {
		return api_error_code.ErrInvalidArguments
	}
	if _, ok = api_auth_common.RequiredString(params, "input"); !ok {
		return api_error_code.ErrInvalidArguments
	}
	if _, ok = api_auth_common.RequiredString(params, "out_dir"); !ok {
		return api_error_code.ErrInvalidArguments
	}
	if version, exists := params["version"]; exists {
		versionText, isString := version.(string)
		if !isString || (versionText != "v1" && versionText != "v2") {
			return api_error_code.ErrInvalidArguments
		}
	}
	if dtype, exists := params["dtype"]; exists {
		dtypeText, isString := dtype.(string)
		if !isString || (dtypeText != "bf16" && dtypeText != "fp32") {
			return api_error_code.ErrInvalidArguments
		}
	}
	return nil
}

func schemaWithDesc(schema map[string]interface{}, description string) map[string]interface{} {
	schema["description"] = description
	return schema
}

func integerSchema() map[string]interface{} {
	return map[string]interface{}{"type": "integer"}
}

func booleanSchema() map[string]interface{} {
	return map[string]interface{}{"type": "boolean"}
}
