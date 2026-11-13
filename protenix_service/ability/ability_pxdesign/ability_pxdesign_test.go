package ability_pxdesign

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/0xdevelop/protenix_service/api/api_error_code"
	"github.com/0xdevelop/protenix_service/config"
)

func TestExecuteValidatesAndRejectsUnconfigured(t *testing.T) {
	if _, err := Execute(context.Background(), map[string]interface{}{"dump_dir": "out"}); err != api_error_code.ErrInvalidArguments {
		t.Fatalf("missing input must be invalid arguments: %v", err)
	}
	if _, err := Execute(context.Background(), map[string]interface{}{"input": "in.yaml", "dump_dir": "out", "preset": "nope"}); err != api_error_code.ErrInvalidArguments {
		t.Fatalf("invalid preset must be rejected: %v", err)
	}
	previous := config.GlobalConfig
	t.Cleanup(func() { config.GlobalConfig = previous })
	config.GlobalConfig = &config.FileConfig{CliCfg: config.DefaultCLIConfig()}
	_, err := Execute(context.Background(), map[string]interface{}{"input": "in.yaml", "dump_dir": "out", "preset": "preview"})
	if err == nil || !strings.Contains(err.Error(), "CLI binary is not configured") {
		t.Fatalf("valid args without binary must return not-configured error: %v", err)
	}
}

func TestBuildArgvStagesInputAndKeepsPreset(t *testing.T) {
	work := t.TempDir()
	src := filepath.Join(work, "task.yaml")
	if err := os.WriteFile(src, []byte("name: src\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	previous := config.GlobalConfig
	t.Cleanup(func() { config.GlobalConfig = previous })
	config.GlobalConfig = &config.FileConfig{CliCfg: &config.CLIConfig{
		WorkRoot:           filepath.Join(work, "jobs"),
		CancelGraceSeconds: 1,
		PXDesign:           &config.CLIBinaryConfig{Binary: dummyRun(t)},
	}}
	argv, err := BuildArgvForTest(context.Background(), map[string]interface{}{
		"input":    src,
		"dump_dir": "caller-out",
		"preset":   "preview",
		"N_sample": 2,
		"dtype":    "bf16",
	})
	if err != nil {
		t.Fatal(err)
	}
	if argv[1] != "pipeline" || flagValue(argv, "--preset") != "preview" || flagValue(argv, "--N_sample") != "2" || flagValue(argv, "--dtype") != "bf16" {
		t.Fatalf("unexpected argv: %v", argv)
	}
	if strings.Contains(strings.Join(argv, " "), "caller-out") {
		t.Fatalf("caller dump_dir must not be used as CLI path: %v", argv)
	}
	inputPath := flagValue(argv, "--input")
	if inputPath == src || !strings.Contains(inputPath, filepath.Join(work, "jobs")) {
		t.Fatalf("input must be staged, got %s", inputPath)
	}
}

func TestExecuteRunsConfiguredDummy(t *testing.T) {
	work := t.TempDir()
	src := filepath.Join(work, "task.yaml")
	if err := os.WriteFile(src, []byte("name: src\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	previous := config.GlobalConfig
	t.Cleanup(func() { config.GlobalConfig = previous })
	config.GlobalConfig = &config.FileConfig{CliCfg: &config.CLIConfig{
		WorkRoot:           filepath.Join(work, "jobs"),
		CancelGraceSeconds: 1,
		PXDesign: &config.CLIBinaryConfig{
			Binary:   dummyRun(t),
			ExtraEnv: map[string]string{"DUMMY_WRITE_CIF": "1"},
		},
	}}
	value, err := Execute(context.Background(), map[string]interface{}{
		"input":    src,
		"dump_dir": "out",
		"preset":   "preview",
	})
	if err != nil {
		t.Fatalf("dummy execute: %v", err)
	}
	payload := value.(map[string]interface{})
	if payload["exit_code"] != 0 || payload["cif_count"] != 1 {
		t.Fatalf("unexpected payload: %+v", payload)
	}
}

func TestExecuteCancelStopsDummyProcess(t *testing.T) {
	work := t.TempDir()
	src := filepath.Join(work, "task.yaml")
	if err := os.WriteFile(src, []byte("name: src\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	previous := config.GlobalConfig
	t.Cleanup(func() { config.GlobalConfig = previous })
	config.GlobalConfig = &config.FileConfig{CliCfg: &config.CLIConfig{
		WorkRoot:           filepath.Join(work, "jobs"),
		CancelGraceSeconds: 1,
		PXDesign: &config.CLIBinaryConfig{
			Binary:   dummyRun(t),
			ExtraEnv: map[string]string{"DUMMY_SLEEP": "1"},
		},
	}}
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	value, err := Execute(ctx, map[string]interface{}{"input": src, "dump_dir": "out"})
	if err == nil || !strings.Contains(err.Error(), "cancelled") {
		t.Fatalf("expected cancel, err=%v value=%v", err, value)
	}
}

func dummyRun(t *testing.T) string {
	t.Helper()
	path := filepath.Join("testdata", "dummy-run.sh")
	if err := os.Chmod(path, 0o755); err != nil {
		t.Fatal(err)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		t.Fatal(err)
	}
	return abs
}

func flagValue(argv []string, name string) string {
	for i, arg := range argv {
		if arg == name && i+1 < len(argv) {
			return argv[i+1]
		}
	}
	return ""
}
