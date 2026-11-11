// Package clisupervisor：systemd Type=simple 主进程骨架。
// 常驻后调用上游 CLI（第一阶段：--help 冒烟，输出进 journal），再阻塞等信号。
package clisupervisor

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Run 启动常驻 supervisor。
// cliName：上游 console_script（protenix / pxdesign）。
// helpArgs：第一阶段冒烟参数，默认 []string{"--help"}。
func Run(daemonName, cliName string, helpArgs []string) error {
	if len(helpArgs) == 0 {
		helpArgs = []string{"--help"}
	}

	prefix := strings.TrimSpace(os.Getenv("SUPERVISOR_PREFIX"))
	if prefix == "" {
		prefix = strings.TrimSpace(os.Getenv(strings.ToUpper(cliName) + "_PREFIX"))
	}

	logf("%s starting; cli=%s prefix=%s", daemonName, cliName, prefix)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	cliPath, err := resolveCLI(cliName, prefix)
	if err != nil {
		logf("warning: %v (still resident; install prefix then restart)", err)
	} else {
		if err := runHelp(ctx, cliPath, helpArgs); err != nil {
			logf("warning: %s %v failed: %v", cliPath, helpArgs, err)
		} else {
			logf("smoke ok: %s %s", cliPath, strings.Join(helpArgs, " "))
		}
	}

	logf("%s resident (Type=simple); waiting for SIGTERM/SIGINT", daemonName)
	<-ctx.Done()
	logf("%s shutting down", daemonName)
	return nil
}

func resolveCLI(cliName, prefix string) (string, error) {
	candidates := []string{}
	if prefix != "" {
		candidates = append(candidates,
			filepath.Join(prefix, "venv", "bin", cliName),
			filepath.Join(prefix, "bin", cliName),
		)
	}
	if p, err := exec.LookPath(cliName); err == nil {
		candidates = append(candidates, p)
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return c, nil
		}
	}
	return "", fmt.Errorf("%s CLI not found in PATH or prefix venv (run scripts/install_prefix_*.sh)", cliName)
}

func runHelp(ctx context.Context, cliPath string, args []string) error {
	cctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cctx, cliPath, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stdout, "[%s] %s\n", time.Now().UTC().Format(time.RFC3339), fmt.Sprintf(format, args...))
}
