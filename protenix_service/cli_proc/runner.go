package cli_proc

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var ErrCancelled = errors.New("cli process group cancelled")

// Spec 描述一次独立进程组内的命令执行。
type Spec struct {
	Name    string
	Path    string
	Args    []string
	Env     map[string]string
	Dir     string
	LogPath string
	Grace   time.Duration
}

// Result 是命令结束后的实测摘要，成功不能只看退出码。
type Result struct {
	PID       int
	PGID      int
	ExitCode  int
	Cancelled bool
	Duration  time.Duration
	LogPath   string
}

// InspectOutput 统计输出目录中的 CIF 与 ERR，供原生结果核验。
func InspectOutput(outDir string) (cifCount int, hasERR bool, err error) {
	if strings.TrimSpace(outDir) == "" {
		return 0, false, nil
	}
	info, statErr := os.Stat(outDir)
	if statErr != nil {
		if os.IsNotExist(statErr) {
			return 0, false, nil
		}
		return 0, false, statErr
	}
	if !info.IsDir() {
		return 0, false, fmt.Errorf("output path is not a directory: %s", outDir)
	}
	walkErr := filepath.WalkDir(outDir, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		name := entry.Name()
		if entry.IsDir() && name == "ERR" {
			hasERR = true
			return nil
		}
		if !entry.IsDir() && filepath.Ext(name) == ".cif" {
			cifCount++
		}
		return nil
	})
	return cifCount, hasERR, walkErr
}

// Run 在新进程组中启动命令。context 取消时先向整个进程组发 SIGTERM，超时后再发 SIGKILL。
// 这不是对包装子壳单独发信号。调用方若传入不会取消的 context，则本函数不会主动取消进程组。
func Run(ctx context.Context, spec Spec) (*Result, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if strings.TrimSpace(spec.Path) == "" {
		return nil, fmt.Errorf("cli binary path is required")
	}
	grace := spec.Grace
	if grace <= 0 {
		grace = 10 * time.Second
	}
	attr, err := newSysProcAttr()
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(spec.Path, spec.Args...)
	cmd.Dir = spec.Dir
	cmd.SysProcAttr = attr
	cmd.Env = os.Environ()
	for key, value := range spec.Env {
		cmd.Env = append(cmd.Env, key+"="+value)
	}
	if strings.TrimSpace(spec.LogPath) != "" {
		if err = os.MkdirAll(filepath.Dir(spec.LogPath), 0o755); err != nil {
			return nil, err
		}
		logFile, openErr := os.OpenFile(spec.LogPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if openErr != nil {
			return nil, openErr
		}
		defer logFile.Close()
		cmd.Stdout = logFile
		cmd.Stderr = logFile
	}
	started := time.Now()
	if err = cmd.Start(); err != nil {
		return nil, err
	}
	result := &Result{PID: cmd.Process.Pid, PGID: cmd.Process.Pid, LogPath: spec.LogPath}
	done := make(chan error, 1)
	go func() {
		done <- cmd.Wait()
	}()
	select {
	case waitErr := <-done:
		reaped := reapLeftoverProcessGroup(cmd.Process.Pid, grace)
		result.Duration = time.Since(started)
		result.ExitCode = exitCode(waitErr)
		if reaped {
			return result, fmt.Errorf("cli wrapper exited but leftover process group members were reaped: pgid=%d", result.PGID)
		}
		if waitErr != nil && result.ExitCode == 0 {
			return result, waitErr
		}
		return result, nil
	case <-ctx.Done():
		result.Cancelled = true
		_ = signalProcessGroup(cmd.Process.Pid, termSignal())
		select {
		case waitErr := <-done:
			result.Duration = time.Since(started)
			result.ExitCode = exitCode(waitErr)
			if result.ExitCode == 0 && waitErr != nil {
				return result, fmt.Errorf("%w: %v", ErrCancelled, waitErr)
			}
			return result, fmt.Errorf("%w", ErrCancelled)
		case <-time.After(grace):
			_ = signalProcessGroup(cmd.Process.Pid, killSignal())
			waitErr := <-done
			result.Duration = time.Since(started)
			result.ExitCode = exitCode(waitErr)
			return result, fmt.Errorf("%w", ErrCancelled)
		}
	}
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}
