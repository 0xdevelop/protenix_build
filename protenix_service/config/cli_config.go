package config

// CLIConfig 是原生 CLI 接线的结构化配置。版本/模型/preset 仍走方法 arguments，不进路径。
type CLIConfig struct {
	WorkRoot           string           `yaml:"work_root" json:"work_root" toml:"work_root" comment:"每任务作业目录的根路径；输入会拷贝到子目录，不改原文件"`
	CancelGraceSeconds int              `yaml:"cancel_grace_seconds" json:"cancel_grace_seconds" toml:"cancel_grace_seconds" comment:"向进程组发送 SIGTERM 后、再发 SIGKILL 的等待秒数"`
	Protenix           *CLIBinaryConfig `yaml:"protenix" json:"protenix" toml:"protenix" comment:"protenix-run 可执行文件；路径为空时 Execute 拒绝启动进程"`
	PXDesign           *CLIBinaryConfig `yaml:"pxdesign" json:"pxdesign" toml:"pxdesign" comment:"pxdesign-run 可执行文件；路径为空时 Execute 拒绝启动进程"`
}

// CLIBinaryConfig 指向已安装的官方包装命令，不在代码里写死路径。
type CLIBinaryConfig struct {
	Binary   string            `yaml:"binary" json:"binary" toml:"binary"`
	ExtraEnv map[string]string `yaml:"extra_env" json:"extra_env" toml:"extra_env" comment:"额外环境变量，例如 LAYERNORM_TYPE=torch"`
}

func DefaultCLIConfig() *CLIConfig {
	return &CLIConfig{
		WorkRoot:           "./data/cli_jobs",
		CancelGraceSeconds: 10,
		Protenix:           &CLIBinaryConfig{ExtraEnv: map[string]string{}},
		PXDesign:           &CLIBinaryConfig{ExtraEnv: map[string]string{}},
	}
}
