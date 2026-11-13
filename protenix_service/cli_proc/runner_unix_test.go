//go:build unix

package cli_proc

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestRunCompletesWithoutCancel(t *testing.T) {
	work := t.TempDir()
	result, err := Run(context.Background(), Spec{
		Path:    wrapperPath(t),
		Args:    []string{"ok"},
		LogPath: filepath.Join(work, "run.log"),
		Grace:   time.Second,
	})
	if err != nil {
		t.Fatalf("expected success: %v", err)
	}
	if result.Cancelled || result.ExitCode != 0 || result.PID <= 0 {
		t.Fatalf("unexpected result: %+v", result)
	}
	body, _ := os.ReadFile(result.LogPath)
	if !strings.Contains(string(body), "wrapper-ok") {
		t.Fatalf("log missing wrapper output: %s", body)
	}
}

func TestCancelSignalsWholeProcessGroup(t *testing.T) {
	work := t.TempDir()
	childPIDFile := filepath.Join(work, "child.pid")
	heartbeat := filepath.Join(work, "heartbeat.txt")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	var result *Result
	var runErr error
	go func() {
		defer close(done)
		result, runErr = Run(ctx, Spec{
			Path: wrapperPath(t),
			Env: map[string]string{
				"CHILD_SCRIPT":   childPath(t),
				"CHILD_PID_FILE": childPIDFile,
				"HEARTBEAT_FILE": heartbeat,
			},
			LogPath: filepath.Join(work, "run.log"),
			Grace:   time.Second,
		})
	}()
	childPID := waitForPIDFile(t, childPIDFile)
	if !processExists(childPID) {
		t.Fatalf("child %d should be running before cancel", childPID)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
	if runErr == nil || !strings.Contains(runErr.Error(), "cancelled") || result == nil || !result.Cancelled {
		t.Fatalf("expected cancelled result, err=%v result=%+v", runErr, result)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !processExists(childPID) && (result.PID == 0 || !processExists(result.PID)) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("process group still alive after cancel: wrapper=%d child=%d", result.PID, childPID)
}

func TestSignalWrapperOnlyLeavesChildRunning(t *testing.T) {
	work := t.TempDir()
	childPIDFile := filepath.Join(work, "child.pid")
	heartbeat := filepath.Join(work, "heartbeat.txt")
	cmd := exec.Command(wrapperPath(t))
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Env = append(os.Environ(),
		"CHILD_SCRIPT="+childPath(t),
		"CHILD_PID_FILE="+childPIDFile,
		"HEARTBEAT_FILE="+heartbeat,
	)
	cmd.Dir = work
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	childPID := waitForPIDFile(t, childPIDFile)
	wrapperPID := cmd.Process.Pid
	t.Cleanup(func() {
		_ = signalProcessGroup(wrapperPID, syscall.SIGKILL)
		_ = cmd.Wait()
	})
	if err := signalProcess(wrapperPID, syscall.SIGTERM); err != nil {
		t.Fatalf("signal wrapper: %v", err)
	}
	time.Sleep(400 * time.Millisecond)
	if !processExists(childPID) {
		t.Fatalf("child %d should still run after SIGTERM only to wrapper %d (old boundary)", childPID, wrapperPID)
	}
}

func TestRunReapsLeftoversWhenWrapperDies(t *testing.T) {
	work := t.TempDir()
	childPIDFile := filepath.Join(work, "child.pid")
	heartbeat := filepath.Join(work, "heartbeat.txt")
	done := make(chan struct{})
	var result *Result
	var runErr error
	go func() {
		defer close(done)
		result, runErr = Run(context.Background(), Spec{
			Path: wrapperPath(t),
			Env: map[string]string{
				"CHILD_SCRIPT":   childPath(t),
				"CHILD_PID_FILE": childPIDFile,
				"HEARTBEAT_FILE": heartbeat,
			},
			LogPath: filepath.Join(work, "run.log"),
			Grace:   time.Second,
		})
	}()
	childPID := waitForPIDFile(t, childPIDFile)
	wrapperPID := waitForWrapperPID(t, childPID)
	if err := signalProcess(wrapperPID, syscall.SIGTERM); err != nil {
		t.Fatalf("signal wrapper: %v", err)
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after wrapper exit")
	}
	if runErr == nil || !strings.Contains(runErr.Error(), "leftover process group") || result == nil {
		t.Fatalf("expected leftover reap error, err=%v result=%+v", runErr, result)
	}
	if processExists(childPID) {
		t.Fatalf("child %d should have been reaped by Run", childPID)
	}
}

func TestStageInputCopiesAndLeavesOriginalUnchanged(t *testing.T) {
	srcDir := t.TempDir()
	src := filepath.Join(srcDir, "input.json")
	original := []byte(`{"name":"original"}`)
	if err := os.WriteFile(src, original, 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(src)
	if err != nil {
		t.Fatal(err)
	}
	work := t.TempDir()
	jobDir, staged, err := StageInput(work, "task-1", src)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(staged, jobDir) {
		t.Fatalf("staged path must be under job dir: %s %s", staged, jobDir)
	}
	copied, err := os.ReadFile(staged)
	if err != nil {
		t.Fatal(err)
	}
	if string(copied) != string(original) {
		t.Fatalf("copied content mismatch: %s", copied)
	}
	if err := os.WriteFile(staged, []byte(`{"name":"changed"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(original) {
		t.Fatalf("original input was modified: %s", after)
	}
	later, err := os.Stat(src)
	if err != nil {
		t.Fatal(err)
	}
	if later.ModTime().Unix() != info.ModTime().Unix() {
		t.Fatalf("original mtime changed: %v -> %v", info.ModTime(), later.ModTime())
	}
}

func TestInspectOutputCountsCIFAndERR(t *testing.T) {
	out := t.TempDir()
	if err := os.WriteFile(filepath.Join(out, "a.cif"), []byte("data_"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(out, "ERR"), 0o755); err != nil {
		t.Fatal(err)
	}
	cif, hasERR, err := InspectOutput(out)
	if err != nil || cif != 1 || !hasERR {
		t.Fatalf("inspect: cif=%d hasERR=%v err=%v", cif, hasERR, err)
	}
}

func wrapperPath(t *testing.T) string {
	t.Helper()
	path := filepath.Join("testdata", "wrapper.sh")
	if err := os.Chmod(path, 0o755); err != nil {
		t.Fatal(err)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		t.Fatal(err)
	}
	return abs
}

func childPath(t *testing.T) string {
	t.Helper()
	path := filepath.Join("testdata", "child.sh")
	if err := os.Chmod(path, 0o755); err != nil {
		t.Fatal(err)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		t.Fatal(err)
	}
	return abs
}

func waitForPIDFile(t *testing.T, path string) int {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		body, err := os.ReadFile(path)
		if err == nil {
			pid, convErr := strconv.Atoi(strings.TrimSpace(string(body)))
			if convErr == nil && pid > 0 && processExists(pid) {
				return pid
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for pid file %s", path)
	return 0
}

func waitForWrapperPID(t *testing.T, childPID int) int {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		body, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(childPID), "stat"))
		if err == nil {
			fields := strings.Fields(string(body))
			if len(fields) > 3 {
				ppid, convErr := strconv.Atoi(fields[3])
				if convErr == nil && ppid > 1 && processExists(ppid) {
					return ppid
				}
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out resolving wrapper pid for child %d", childPID)
	return 0
}
