//go:build ignore

// gen_pre_build_config.go：从模板生成/校验固化 YAML，或导出供 build.sh source 的 shell 变量。
// 只由 gen_pre_build_config.sh 经 `go run` 调用；不进任何服务二进制。
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	templateFile = "pre_build_config_template.yaml"
)

type preBuildConfig struct {
	Project struct {
		Name    string `yaml:"name"`
		Version string `yaml:"version"`
	} `yaml:"project"`
	RunMode string `yaml:"run_mode"`
	Target  struct {
		Goos   string `yaml:"goos"`
		Goarch string `yaml:"goarch"`
	} `yaml:"target"`
	InstallPrefix string `yaml:"install_prefix"`
	HostCapability struct {
		CUDA              string `yaml:"cuda"`
		PythonHostAnchor  string `yaml:"python_host_anchor"`
		NodeLTS           string `yaml:"node_lts"`
		ProductPythonMin  string `yaml:"product_python_min"`
		ProductPythonMax  string `yaml:"product_python_max"`
		Note              string `yaml:"note"`
	} `yaml:"host_capability"`
	EnvStrategy              string        `yaml:"env_strategy"`
	EnvStrategyNote          string        `yaml:"env_strategy_note"`
	Products                 []productSpec `yaml:"products"`
	Paths                    pathSpec      `yaml:"paths"`
	SkipPrefixInstallInBuild bool          `yaml:"skip_prefix_install_in_build"`
	Delivery                 string        `yaml:"delivery"`
}

type productSpec struct {
	Name                string `yaml:"name"`
	SrcPath             string `yaml:"src_path"`
	BuildSubdir         string `yaml:"build_subdir"`
	ServiceUnit         string `yaml:"service_unit"`
	OneshotUnit         string `yaml:"oneshot_unit"`
	EnvFile             string `yaml:"env_file"`
	Wrapper             string `yaml:"wrapper"`
	InstallScript       string `yaml:"install_script"`
	PrefixInstallScript string `yaml:"prefix_install_script"`
	EnvPolicy           string `yaml:"env_policy"`
	PinnedProtenixRef   string `yaml:"pinned_protenix_ref"`
	TorchHint           string `yaml:"torch_hint"`
	CLIName             string `yaml:"cli_name"`
	WrapperName         string `yaml:"wrapper_name"`
	SupervisorBin       string `yaml:"supervisor_bin"`
	SupervisorCmdPath   string `yaml:"supervisor_cmd_path"`
	SystemdType         string `yaml:"systemd_type"`
	ProductPython       string `yaml:"product_python"`
}

type pathSpec struct {
	BuildRoot        string `yaml:"build_root"`
	UploadTmpDir     string `yaml:"upload_tmp_dir"`
	PrefixRoot       string `yaml:"prefix_root"`
	ExampleFilesDir  string `yaml:"example_files_dir"`
	ScriptsDir       string `yaml:"scripts_dir"`
}

func main() {
	validatePath := flag.String("validate", "", "校验已有 gen yaml 路径")
	exportPath := flag.String("export", "", "导出 shell 变量（供 build.sh source）")
	target := flag.String("target", "", "生成目标：linux_amd64 或 linux_arm64")
	flag.Parse()

	root, err := os.Getwd()
	if err != nil {
		fail(err.Error())
	}

	switch {
	case *validatePath != "":
		cfg, err := loadConfig(filepath.Join(root, *validatePath))
		if err != nil {
			fail(err.Error())
		}
		if err := validateConfig(cfg, true); err != nil {
			fail(err.Error())
		}
		fmt.Printf("[gen_pre_build_config] ok validate %s (%s/%s, %d products)\n",
			*validatePath, cfg.Target.Goos, cfg.Target.Goarch, len(cfg.Products))
	case *exportPath != "":
		cfg, err := loadConfig(filepath.Join(root, *exportPath))
		if err != nil {
			fail(err.Error())
		}
		if err := validateConfig(cfg, true); err != nil {
			fail(err.Error())
		}
		printExport(cfg)
	case *target != "":
		goos, goarch, outName, err := parseTarget(*target)
		if err != nil {
			fail(err.Error())
		}
		outPath := filepath.Join(root, outName)
		if err := generateFromTemplate(root, goos, goarch, outPath); err != nil {
			fail(err.Error())
		}
		cfg, err := loadConfig(outPath)
		if err != nil {
			fail(err.Error())
		}
		if err := validateConfig(cfg, true); err != nil {
			fail(err.Error())
		}
		fmt.Printf("[gen_pre_build_config] wrote %s (%s/%s)\n", outName, goos, goarch)
	default:
		fmt.Fprintf(os.Stderr, "usage:\n")
		fmt.Fprintf(os.Stderr, "  go run gen_pre_build_config.go -target linux_amd64|linux_arm64\n")
		fmt.Fprintf(os.Stderr, "  go run gen_pre_build_config.go -validate gen_pre_build_config_linux_amd64.yaml\n")
		fmt.Fprintf(os.Stderr, "  go run gen_pre_build_config.go -export gen_pre_build_config_linux_amd64.yaml\n")
		os.Exit(2)
	}
}

func parseTarget(t string) (goos, goarch, outName string, err error) {
	switch t {
	case "linux_amd64":
		return "linux", "amd64", "gen_pre_build_config_linux_amd64.yaml", nil
	case "linux_arm64":
		return "linux", "arm64", "gen_pre_build_config_linux_arm64.yaml", nil
	default:
		return "", "", "", fmt.Errorf("unsupported target %q (want linux_amd64|linux_arm64)", t)
	}
}

func generateFromTemplate(root, goos, goarch, outPath string) error {
	raw, err := os.ReadFile(filepath.Join(root, templateFile))
	if err != nil {
		return err
	}
	text := string(raw)
	text = strings.ReplaceAll(text, "{{GOOS}}", goos)
	text = strings.ReplaceAll(text, "{{GOARCH}}", goarch)
	header := fmt.Sprintf("# 由 gen_pre_build_config 固化：%s/%s\n# 双环境策略见 env_strategy_note；本文件可手改后由工具 -validate 校验。\n\n", goos, goarch)
	// 去掉模板头注释块，避免与固化头重复堆叠
	lines := strings.Split(text, "\n")
	start := 0
	for start < len(lines) {
		trim := strings.TrimSpace(lines[start])
		if trim == "" || strings.HasPrefix(trim, "#") {
			start++
			continue
		}
		break
	}
	body := strings.Join(lines[start:], "\n")
	return os.WriteFile(outPath, []byte(header+body), 0o644)
}

func loadConfig(path string) (*preBuildConfig, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg preBuildConfig
	if err := yaml.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &cfg, nil
}

func validateConfig(cfg *preBuildConfig, requireConcreteTarget bool) error {
	if cfg.Project.Name == "" {
		return fmt.Errorf("project.name required")
	}
	if cfg.Project.Version == "" {
		return fmt.Errorf("project.version required")
	}
	if cfg.RunMode == "" {
		return fmt.Errorf("run_mode required")
	}
	switch cfg.RunMode {
	case "release", "test", "debug":
	default:
		return fmt.Errorf("run_mode must be release|test|debug, got %q", cfg.RunMode)
	}
	if cfg.InstallPrefix == "" {
		return fmt.Errorf("install_prefix required")
	}
	if cfg.EnvStrategy == "" {
		return fmt.Errorf("env_strategy required")
	}
	if cfg.HostCapability.CUDA == "" || cfg.HostCapability.PythonHostAnchor == "" || cfg.HostCapability.NodeLTS == "" {
		return fmt.Errorf("host_capability.cuda / python_host_anchor / node_lts required")
	}
	if cfg.HostCapability.ProductPythonMin == "" || cfg.HostCapability.ProductPythonMax == "" {
		return fmt.Errorf("host_capability.product_python_min/max required")
	}
	if requireConcreteTarget {
		if cfg.Target.Goos == "" || strings.Contains(cfg.Target.Goos, "{{") {
			return fmt.Errorf("target.goos must be concrete")
		}
		if cfg.Target.Goarch == "" || strings.Contains(cfg.Target.Goarch, "{{") {
			return fmt.Errorf("target.goarch must be concrete")
		}
		if cfg.Target.Goos != "linux" {
			return fmt.Errorf("this stage only supports goos=linux, got %q", cfg.Target.Goos)
		}
		switch cfg.Target.Goarch {
		case "amd64", "arm64":
		default:
			return fmt.Errorf("this stage only supports goarch=amd64|arm64, got %q", cfg.Target.Goarch)
		}
	}
	if cfg.Paths.BuildRoot == "" || cfg.Paths.UploadTmpDir == "" {
		return fmt.Errorf("paths.build_root and paths.upload_tmp_dir required")
	}
	if len(cfg.Products) == 0 {
		return fmt.Errorf("products required")
	}
	seen := map[string]bool{}
	haveProtenix, havePXDesign := false, false
	for i, p := range cfg.Products {
		if p.Name == "" {
			return fmt.Errorf("products[%d].name required", i)
		}
		if seen[p.Name] {
			return fmt.Errorf("duplicate product name %q", p.Name)
		}
		seen[p.Name] = true
		for _, field := range []struct {
			k, v string
		}{
			{"src_path", p.SrcPath},
			{"build_subdir", p.BuildSubdir},
			{"service_unit", p.ServiceUnit},
			{"oneshot_unit", p.OneshotUnit},
			{"env_file", p.EnvFile},
			{"wrapper", p.Wrapper},
			{"install_script", p.InstallScript},
			{"prefix_install_script", p.PrefixInstallScript},
			{"env_policy", p.EnvPolicy},
			{"cli_name", p.CLIName},
			{"wrapper_name", p.WrapperName},
			{"supervisor_bin", p.SupervisorBin},
			{"supervisor_cmd_path", p.SupervisorCmdPath},
			{"systemd_type", p.SystemdType},
			{"product_python", p.ProductPython},
		} {
			if field.v == "" {
				return fmt.Errorf("products[%s].%s required", p.Name, field.k)
			}
		}
		// 主 unit 为 simple + Go supervisor；oneshot_unit 仅批作业模板
		if p.SystemdType != "simple" {
			return fmt.Errorf("products[%s].systemd_type must be simple (Go supervisor resident), got %q", p.Name, p.SystemdType)
		}
		switch p.Name {
		case "protenix":
			haveProtenix = true
			if p.EnvPolicy != "latest_submodule" {
				return fmt.Errorf("protenix.env_policy must be latest_submodule")
			}
		case "pxdesign":
			havePXDesign = true
			if p.EnvPolicy != "pinned_protenix_v0_5_0_pxd" {
				return fmt.Errorf("pxdesign.env_policy must be pinned_protenix_v0_5_0_pxd")
			}
			if p.PinnedProtenixRef == "" {
				return fmt.Errorf("pxdesign.pinned_protenix_ref required")
			}
		}
	}
	if !haveProtenix || !havePXDesign {
		return fmt.Errorf("products must include both protenix and pxdesign")
	}
	return nil
}

func printExport(cfg *preBuildConfig) {
	escape := func(s string) string {
		return strings.ReplaceAll(s, `'`, `'"'"'`)
	}
	fmt.Printf("PROJECT_NAME='%s'\n", escape(cfg.Project.Name))
	fmt.Printf("PROJECT_VERSION='%s'\n", escape(cfg.Project.Version))
	fmt.Printf("RUN_MODE='%s'\n", escape(cfg.RunMode))
	fmt.Printf("GOOS_TARGET='%s'\n", escape(cfg.Target.Goos))
	fmt.Printf("GOARCH_TARGET='%s'\n", escape(cfg.Target.Goarch))
	fmt.Printf("INSTALL_PREFIX='%s'\n", escape(cfg.InstallPrefix))
	fmt.Printf("ENV_STRATEGY='%s'\n", escape(cfg.EnvStrategy))
	fmt.Printf("HOST_CUDA='%s'\n", escape(cfg.HostCapability.CUDA))
	fmt.Printf("HOST_PYTHON_ANCHOR='%s'\n", escape(cfg.HostCapability.PythonHostAnchor))
	fmt.Printf("HOST_NODE_LTS='%s'\n", escape(cfg.HostCapability.NodeLTS))
	fmt.Printf("PRODUCT_PYTHON_MIN='%s'\n", escape(cfg.HostCapability.ProductPythonMin))
	fmt.Printf("PRODUCT_PYTHON_MAX='%s'\n", escape(cfg.HostCapability.ProductPythonMax))
	fmt.Printf("BUILD_ROOT='%s'\n", escape(cfg.Paths.BuildRoot))
	fmt.Printf("UPLOAD_TMP_DIR='%s'\n", escape(cfg.Paths.UploadTmpDir))
	fmt.Printf("PREFIX_ROOT='%s'\n", escape(cfg.Paths.PrefixRoot))
	fmt.Printf("DELIVERY='%s'\n", escape(cfg.Delivery))
	if cfg.SkipPrefixInstallInBuild {
		fmt.Printf("SKIP_PREFIX_INSTALL_IN_BUILD='1'\n")
	} else {
		fmt.Printf("SKIP_PREFIX_INSTALL_IN_BUILD='0'\n")
	}
	names := make([]string, 0, len(cfg.Products))
	for _, p := range cfg.Products {
		names = append(names, p.Name)
		prefix := strings.ToUpper(strings.ReplaceAll(p.Name, "-", "_"))
		fmt.Printf("PRODUCT_%s_SRC='%s'\n", prefix, escape(p.SrcPath))
		fmt.Printf("PRODUCT_%s_BUILD_SUBDIR='%s'\n", prefix, escape(p.BuildSubdir))
		fmt.Printf("PRODUCT_%s_SERVICE='%s'\n", prefix, escape(p.ServiceUnit))
		fmt.Printf("PRODUCT_%s_ONESHOT='%s'\n", prefix, escape(p.OneshotUnit))
		fmt.Printf("PRODUCT_%s_ENV='%s'\n", prefix, escape(p.EnvFile))
		fmt.Printf("PRODUCT_%s_WRAPPER='%s'\n", prefix, escape(p.Wrapper))
		fmt.Printf("PRODUCT_%s_INSTALL='%s'\n", prefix, escape(p.InstallScript))
		fmt.Printf("PRODUCT_%s_PREFIX_INSTALL='%s'\n", prefix, escape(p.PrefixInstallScript))
		fmt.Printf("PRODUCT_%s_ENV_POLICY='%s'\n", prefix, escape(p.EnvPolicy))
		fmt.Printf("PRODUCT_%s_CLI='%s'\n", prefix, escape(p.CLIName))
		fmt.Printf("PRODUCT_%s_WRAPPER_NAME='%s'\n", prefix, escape(p.WrapperName))
		fmt.Printf("PRODUCT_%s_SUPERVISOR_BIN='%s'\n", prefix, escape(p.SupervisorBin))
		fmt.Printf("PRODUCT_%s_SUPERVISOR_CMD_PATH='%s'\n", prefix, escape(p.SupervisorCmdPath))
		fmt.Printf("PRODUCT_%s_SYSTEMD_TYPE='%s'\n", prefix, escape(p.SystemdType))
		fmt.Printf("PRODUCT_%s_PRODUCT_PYTHON='%s'\n", prefix, escape(p.ProductPython))
		fmt.Printf("PRODUCT_%s_PINNED_PROTENIX_REF='%s'\n", prefix, escape(p.PinnedProtenixRef))
		fmt.Printf("PRODUCT_%s_TORCH_HINT='%s'\n", prefix, escape(p.TorchHint))
	}
	fmt.Printf("PRODUCT_NAMES='%s'\n", escape(strings.Join(names, " ")))
}

func fail(msg string) {
	fmt.Fprintf(os.Stderr, "[gen_pre_build_config] %s\n", msg)
	os.Exit(1)
}
