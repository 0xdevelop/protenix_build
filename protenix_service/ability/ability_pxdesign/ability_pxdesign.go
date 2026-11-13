// Package ability_pxdesign 注册固定功能入口 pxdesign（MCP tools/call 的 name）。
// preset、输入输出等一律放在 arguments，不进入 URL 或方法路径。
package ability_pxdesign

import (
	"context"
	"errors"

	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_common"
	"github.com/0xdevelop/protenix_service/api/api_error_code"
	"github.com/0xdevelop/protenix_service/api/api_supported_methods"
)

const MethodPXDesign = "pxdesign"

var errNotWiredToCLI = errors.New("pxdesign is not yet wired to the native pxdesign-run CLI")

func LoadAPIMethods() {
	api_supported_methods.AddMethod(&api_supported_methods.SupportedMethod{
		Name:        MethodPXDesign,
		Description: "提交 PXDesign 设计流水线任务（对应 CLI：pxdesign-run pipeline）。本切片尚未接线到原生 CLI；异步队列固定走 MySQL，未启用时受理失败。",
		Async:       true,
		InputSchema: api_auth_common.InputSchema(
			map[string]interface{}{
				"input":      schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "输入 YAML/JSON 文件。对应 CLI -i/--input。"),
				"dump_dir":   schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "结果输出目录。对应 CLI -o/--dump_dir。"),
				"preset":     schemaWithDesc(api_auth_common.EnumStringSchema("preview", "extended", "custom"), "流水线预设。对应 CLI --preset。"),
				"N_sample":   schemaWithDesc(integerSchema(), "扩散样本数。对应 CLI --N_sample。"),
				"N_step":     schemaWithDesc(integerSchema(), "扩散步数。对应 CLI --N_step。"),
				"N_max_runs": schemaWithDesc(integerSchema(), "最大 design run 数。对应 CLI --N_max_runs。"),
				"dtype":      schemaWithDesc(api_auth_common.EnumStringSchema("fp32", "bf16"), "推理 dtype。对应 CLI --dtype。"),
				"eta_max":    schemaWithDesc(numberSchema(), "eta 调度最大值。对应 CLI --eta_max。"),
				"eta_min":    schemaWithDesc(numberSchema(), "eta 调度最小值。对应 CLI --eta_min。"),
				"eta_type":   schemaWithDesc(api_auth_common.StringSchema("", 1, 64), "eta 调度类型。对应 CLI --eta_type。"),
			},
			"input", "dump_dir",
		),
		Execute: Execute,
	})
}

func Execute(_ context.Context, input interface{}) (interface{}, error) {
	if err := validatePXDesignArgs(input); err != nil {
		return nil, err
	}
	return nil, errNotWiredToCLI
}

func validatePXDesignArgs(input interface{}) error {
	params, ok := api_auth_common.InputObject(input)
	if !ok {
		return api_error_code.ErrInvalidArguments
	}
	if _, ok = api_auth_common.RequiredString(params, "input"); !ok {
		return api_error_code.ErrInvalidArguments
	}
	if _, ok = api_auth_common.RequiredString(params, "dump_dir"); !ok {
		return api_error_code.ErrInvalidArguments
	}
	if preset, exists := params["preset"]; exists {
		presetText, isString := preset.(string)
		if !isString || (presetText != "preview" && presetText != "extended" && presetText != "custom") {
			return api_error_code.ErrInvalidArguments
		}
	}
	if dtype, exists := params["dtype"]; exists {
		dtypeText, isString := dtype.(string)
		if !isString || (dtypeText != "fp32" && dtypeText != "bf16") {
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

func numberSchema() map[string]interface{} {
	return map[string]interface{}{"type": "number"}
}
