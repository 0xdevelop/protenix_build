// Package ability_pxdesign 注册固定功能入口 pxdesign（MCP tools/call 的 name）。
// preset、输入输出等一律放在 arguments，不进入 URL 或方法路径。
package ability_pxdesign

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

const MethodPXDesign = "pxdesign"

var errCLINotConfigured = errors.New("pxdesign CLI binary is not configured")

func LoadAPIMethods() {
	api_supported_methods.AddMethod(&api_supported_methods.SupportedMethod{
		Name:        MethodPXDesign,
		Description: "提交 PXDesign 设计流水线任务（对应 CLI：pxdesign-run pipeline）。preset 走 arguments。异步队列固定走 MySQL，未启用时受理失败。未配置 cli_cfg.pxdesign.binary 时 Execute 拒绝启动进程。",
		Async:       true,
		InputSchema: api_auth_common.InputSchema(
			map[string]interface{}{
				"input":      schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "输入 YAML/JSON 文件。对应 CLI -i/--input。"),
				"dump_dir":   schemaWithDesc(api_auth_common.StringSchema("", 1, 4096), "调用方给出的结果目录名；实际写入隔离作业目录下的 output/。对应 CLI -o/--dump_dir。"),
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

func Execute(ctx context.Context, input interface{}) (interface{}, error) {
	if err := validatePXDesignArgs(input); err != nil {
		return nil, err
	}
	spec, jobDir, outDir, err := buildPXDesignSpec(ctx, input)
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

func buildPXDesignSpec(ctx context.Context, input interface{}) (*cli_proc.Spec, string, string, error) {
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
	args := []string{"pipeline", "--input", stagedInput, "--dump_dir", outDir}
	args, err = appendPXDesignOptionalFlags(args, params)
	if err != nil {
		return nil, "", "", err
	}
	grace := time.Duration(cliCfg.CancelGraceSeconds) * time.Second
	if grace <= 0 {
		grace = 10 * time.Second
	}
	return &cli_proc.Spec{
		Name:    MethodPXDesign,
		Path:    binary.Binary,
		Args:    args,
		Env:     binary.ExtraEnv,
		Dir:     jobDir,
		LogPath: filepath.Join(jobDir, "run.log"),
		Grace:   grace,
	}, jobDir, outDir, nil
}

func appendPXDesignOptionalFlags(args []string, params map[string]interface{}) ([]string, error) {
	if value, ok, err := cli_proc.OptionalString(params, "preset"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--preset", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "N_sample"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--N_sample", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "N_step"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--N_step", value)
	}
	if value, ok, err := cli_proc.OptionalInt(params, "N_max_runs"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendIntFlag(args, "--N_max_runs", value)
	}
	if value, ok, err := cli_proc.OptionalString(params, "dtype"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--dtype", value)
	}
	if value, ok, err := cli_proc.OptionalFloat(params, "eta_max"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFloatFlag(args, "--eta_max", value)
	}
	if value, ok, err := cli_proc.OptionalFloat(params, "eta_min"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFloatFlag(args, "--eta_min", value)
	}
	if value, ok, err := cli_proc.OptionalString(params, "eta_type"); err != nil {
		return nil, err
	} else if ok {
		args = cli_proc.AppendFlag(args, "--eta_type", value)
	}
	return args, nil
}

func configuredBinary() (*config.CLIConfig, *config.CLIBinaryConfig, error) {
	if config.GlobalConfig == nil || config.GlobalConfig.CliCfg == nil || config.GlobalConfig.CliCfg.PXDesign == nil {
		return nil, nil, errCLINotConfigured
	}
	cliCfg := config.GlobalConfig.CliCfg
	if strings.TrimSpace(cliCfg.WorkRoot) == "" {
		cliCfg.WorkRoot = "./data/cli_jobs"
	}
	binary := cliCfg.PXDesign
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

func BuildArgvForTest(ctx context.Context, input interface{}) ([]string, error) {
	spec, _, _, err := buildPXDesignSpec(ctx, input)
	if err != nil {
		return nil, err
	}
	return append([]string{spec.Path}, spec.Args...), nil
}
