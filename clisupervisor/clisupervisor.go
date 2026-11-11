// Package clisupervisor：systemd Type=oneshot 单元的主进程（Go 实现，非常驻）。
//
// 行为（按 2026-11-11 15:50 监督纠正）：
//  1. 定位上游 CLI（prefix/venv/bin/<cli> → prefix/bin/<cli> → PATH）；找不到直接返回 error，进程非零退出，unit 失败。
//  2. 预检：执行 `<cli> --help`（带超时）；失败返回 error，unit 失败。
//  3. 未给作业参数时只做冒烟（第 1、2 步），成功即退出 0——这是“--help 冒烟”层证据，不代表推理可用。
//  4. 给了作业参数时，以子进程运行 `<cli> <args...>`，stdout/stderr 直通 journal；
//     SIGTERM/SIGINT 转发给子进程组；子进程退出码原样作为本进程退出码。
//
// 不做任何空转等待：主进程的生命周期 = 上游 CLI 真实工作的生命周期。
package clisupervisor

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// HelpTimeout 是 `--help` 预检的超时时间（首次 import torch 可能较慢）。
var HelpTimeout = 180 * time.Second

// ExitError 携带应作为进程退出码的值。
type ExitError struct {
	Code int
	Err  error
}

func (e *ExitError) Error() string { return e.Err.Error() }
func (e *ExitError) Unwrap() error { return e.Err }

// ExitCode 返回 err 对应的进程退出码：nil→0，*ExitError→其 Code，其它→1。
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var ee *ExitError
	if errors.As(err, &ee) && ee.Code > 0 {
		return ee.Code
	}
	return 1
}

// Run 执行一次 oneshot：预检 CLI；jobArgs 为空时只冒烟，否则运行真实作业。
func Run(daemonName, cliName string, jobArgs []string) error {
	prefix := strings.TrimSpace(os.Getenv("SUPERVISOR_PREFIX"))
	if prefix == "" {
		prefix = strings.TrimSpace(os.Getenv(strings.ToUpper(cliName) + "_PREFIX"))
	}
	logf("%s start; cli=%s prefix=%q args=%q", daemonName, cliName, prefix, jobArgs)

	cliPath, err := resolveCLI(cliName, prefix)
	if err != nil {
		return &ExitError{Code: 127, Err: err}
	}
	logf("cli resolved: %s", cliPath)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	hctx, cancel := context.WithTimeout(ctx, HelpTimeout)
	defer cancel()
	if err := runChild(hctx, cliPath, []string{"--help"}, true); err != nil {
		return fmt.Errorf("preflight `%s --help` failed: %w", cliPath, err)
	}
	logf("preflight ok: %s --help", cliPath)

	if len(jobArgs) == 0 {
		logf("%s smoke-only run finished (no job args); this proves CLI start-up only, not inference", daemonName)
		return nil
	}

	start := time.Now()
	err = runChild(ctx, cliPath, jobArgs, false)
	logf("%s job finished in %s; err=%v", daemonName, time.Since(start).Round(time.Millisecond), err)
	return err
}

func resolveCLI(cliName, prefix string) (string, error) {
	var candidates []string
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
	return "", fmt.Errorf("%s CLI not found (tried %q and PATH); run scripts/install_prefix_%s.sh first", cliName, candidates, cliName)
}

// runChild 运行子进程（独立进程组）；ctx 取消时先 SIGTERM 整个进程组，30s 后 SIGKILL。
func runChild(ctx context.Context, path string, args []string, quiet bool) error {
	cmd := exec.Command(path, args...)
	cmd.Env = os.Environ()
	cmd.Stderr = os.Stderr
	if quiet {
		cmd.Stdout = nil // --help 的输出不刷进 journal
	} else {
		cmd.Stdout = os.Stdout
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return &ExitError{Code: 126, Err: fmt.Errorf("start %s: %w", path, err)}
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		return wrapWaitErr(path, err)
	case <-ctx.Done():
		logf("context done (%v); sending SIGTERM to process group %d", ctx.Err(), cmd.Process.Pid)
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		select {
		case err := <-done:
			if err == nil {
				err = ctx.Err()
			}
			return wrapWaitErr(path, err)
		case <-time.After(30 * time.Second):
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			<-done
			return &ExitError{Code: 137, Err: fmt.Errorf("%s killed after SIGTERM timeout", path)}
		}
	}
}

func wrapWaitErr(path string, err error) error {
	if err == nil {
		return nil
	}
	var xe *exec.ExitError
	if errors.As(err, &xe) {
		code := xe.ExitCode()
		if code < 0 { // 被信号终止
			code = 128 + 15
			if ws, ok := xe.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
				code = 128 + int(ws.Signal())
			}
		}
		return &ExitError{Code: code, Err: fmt.Errorf("%s exited with code %d", path, code)}
	}
	return err
}

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stdout, "[%s] %s\n", time.Now().UTC().Format(time.RFC3339), fmt.Sprintf(format, args...))
}
