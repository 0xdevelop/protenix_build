// Package ability_protenix 注册固定功能入口 protenix（MCP tools/call 的 name）。
// 版本、模型、输入输出等一律放在 arguments，不进入 URL 或方法路径。
package ability_protenix

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/0xdevelop/protenix_service/ability/ability_task"
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_common"
	"github.com/0xdevelop/protenix_service/api/api_error_code"
	"github.com/0xdevelop/protenix_service/api/api_supported_methods"
	"github.com/0xdevelop/protenix_service/cli_proc"
	"github.com/0xdevelop/protenix_service/config"
	"github.com/google/uuid"
)

const MethodProtenix = "protenix"

var errCLINotConfigured = errors.New("protenix CLI binary is not configured")

func LoadAPIMethods() {
	api_supported_methods.AddMethod(&api_supported_methods.SupportedMethod{
		Name:        MethodProtenix,
		Description: "提交 Protenix 结构预测任务（对应 CLI：protenix-run pred）。版本/模型走 arguments。异步队列固定走 MySQL，未启用时受理失败。未配置 cli_cfg.protenix.binary 时 Execute 拒绝启动进程。",
		Async:       true,
		InputSchema: api_auth_common.InputSchema(
			map[string]interface{}{
				"version":            schemaWithDesc(api_auth_common.EnumStringSchema("v1", "v2"), "产品版本（v1/v2），不是 URL 路径。缺省 v1。v2 需要授权权重。不作为 CLI 开关传入。"),
				"input":              schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "输入 JSON 文件或目录。对应 CLI -i/--input。"),
				"out_dir":            schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "调用方给出的结果目录名；实际写入隔离作业目录下的 output/，不直接改原输入。对应 CLI -o/--out_dir。"),
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

func Execute(ctx context.Context, input interface{}) (interface{}, error) {
	if err := validateProtenixArgs(input); err != nil {
		return nil, err
	}
	spec, jobDir, outDir, err := buildProtenixSpec(ctx, input)
	if err != nil {
		return nil, err
	}
	if err = os.MkdirAll(outDir, 0o755); err != nil {
		return nil, err
	}
	result, runErr := cli_proc.Run(ctx, *spec)
	payload := executionPayload(jobDir, outDir, result)
	if runErr != nil {
		return payload, runErr
	}
	return payload, nil
}

func buildProtenixSpec(ctx context.Context, input interface{}) (*cli_proc.Spec, string, string, error) {
	params, ok := api_auth_common.InputObject(input)
	if !ok {
		return nil, "", "", api_error_code.ErrInvalidArguments
	}
	cliCfg, binary, err := configuredBinary()
	if err != nil {
		return nil, "", "", err
	}
	inputPath, _ := api_auth_common.RequiredString(params, "input")
	taskID := executionTaskID(ctx)
	jobDir, stagedInput, err := cli_proc.StageInput(cliCfg.WorkRoot, taskID, inputPath)
	if err != nil {
		return nil, "", "", err
	}
	outDir := filepath.Join(jobDir, "output")
	args := []string{"pred", "--input", stagedInput, "--out_dir", outDir}
	args, err = appendProtenixOptionalFlags(args, params)
	if err != nil {
		return nil, "", "", err
	}
	grace := time.Duration(cliCfg.CancelGraceSeconds) * time.Second
	if grace <= 0 {
		grace = 10 * time.Second
	}
	return &cli_proc.Spec{
		Name:    MethodProtenix,
		Path:    binary.Binary,
		Args:    args,
		Env:     binary.ExtraEnv,
		Dir:     jobDir,
		LogPath: filepath.Join(jobDir, "run.log"),
		Grace:   grace,
	}, jobDir, outDir, nil
}

func appendProtenixOptionalFlags(args []string, params map[string]interface{}) ([]string, error) {
	if value, ok, err := cli_proc.OptionalString(params, "model_name"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--model_name", value)
	}
	if value, ok, err := cli_proc.OptionalString(params, "seeds"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--seeds", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "cycle"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--cycle", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "step"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--step", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "sample"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--sample", value)
	}
	if value, ok, err := cli_proc.OptionalString(params, "dtype"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--dtype", value)
	}
	if value, ok, err := cli_proc.OptionalBool(params, "use_msa"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendBoolFlag(args, "--use_msa", value)
	}
	if value, ok, err := cli_proc.OptionalBool(params, "use_default_params"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendBoolFlag(args, "--use_default_params", value)
	}
	return args, nil
}

func configuredBinary() (*config.CLIConfig, *config.CLIBinaryConfig, error) {
	if config.GlobalConfig == nil || config.GlobalConfig.CliCfg == nil || config.GlobalConfig.CliCfg.Protenix == nil {
		return nil, nil, errCLINotConfigured
	}
	cliCfg := config.GlobalConfig.CliCfg
	if strings.TrimSpace(cliCfg.WorkRoot) == "" {
		cliCfg.WorkRoot = "./data/cli_jobs"
	}
	binary := cliCfg.Protenix
	if strings.TrimSpace(binary.Binary) == "" {
		return nil, nil, errCLINotConfigured
	}
	return cliCfg, binary, nil
}

func executionTaskID(ctx context.Context) string {
	if info, ok := ability_task.AsyncTaskInfoFromContext(ctx); ok && info.TaskID != "" {
		return info.TaskID
	}
	return "direct-" + uuid.NewString()
}

func executionPayload(jobDir, outDir string, result *cli_proc.Result) map[string]interface{} {
	payload := map[string]interface{}{
		"job_dir": jobDir,
		"out_dir": outDir,
	}
	if result != nil {
		payload["pid"] = result.PID
		payload["pgid"] = result.PGID
		payload["exit_code"] = result.ExitCode
		payload["cancelled"] = result.Cancelled
		payload["log_path"] = result.LogPath
	}
	cifCount, hasERR, err := cli_proc.InspectOutput(outDir)
	if err == nil {
		payload["cif_count"] = cifCount
		payload["has_err"] = hasERR
	}
	return payload
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

// BuildArgvForTest 导出给测试：确认 version 不进入 CLI 参数。
func BuildArgvForTest(ctx context.Context, input interface{}) ([]string, error) {
	spec, _, _, err := buildProtenixSpec(ctx, input)
	if err != nil {
		return nil, err
	}
	return append([]string{spec.Path}, spec.Args...), nil
}
