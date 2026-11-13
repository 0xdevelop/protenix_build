package ability_protenix

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/0xdevelop/protenix_service/ability/ability_pxdesign"
	"github.com/0xdevelop/protenix_service/api/api_auth/api_auth_config"
	"github.com/0xdevelop/protenix_service/api/api_error_code"
	"github.com/0xdevelop/protenix_service/api/api_executer"
	"github.com/0xdevelop/protenix_service/api/api_supported_methods"
	"github.com/0xdevelop/protenix_service/config"
	"github.com/0xdevelop/protenix_service/storage"
	"github.com/0xdevelop/protenix_service/storage/storage_config"
	"github.com/george012/gtbox/gtbox_orm/gtbox_orm_sqlite"
)

func TestExecuteValidatesAndRejectsUnwired(t *testing.T) {
	if _, err := Execute(context.Background(), map[string]interface{}{"out_dir": "out"}); err != api_error_code.ErrInvalidArguments {
		t.Fatalf("missing input must be invalid arguments: %v", err)
	}
	if _, err := Execute(context.Background(), map[string]interface{}{"input": "in.json", "out_dir": "out", "version": "v3"}); err != api_error_code.ErrInvalidArguments {
		t.Fatalf("invalid version must be rejected: %v", err)
	}
	_, err := Execute(context.Background(), map[string]interface{}{"input": "in.json", "out_dir": "out", "version": "v1"})
	if err == nil || !strings.Contains(err.Error(), "not yet wired") {
		t.Fatalf("valid args must return not-wired error: %v", err)
	}
}

func TestAsyncAcceptRejectsSqliteWithoutMysql(t *testing.T) {
	previous := config.GlobalConfig
	previousAuth := api_auth_config.CurrentCfgAuth
	t.Cleanup(func() {
		_ = storage.CloseStorage()
		config.GlobalConfig = previous
		api_auth_config.CurrentCfgAuth = previousAuth
	})

	config.GlobalConfig = &config.FileConfig{StorageCfg: &storage_config.StorageConfig{
		Primary: "sqlite",
		Sqlite: &storage_config.StorageSqliteConfig{
			Enabled:           true,
			GTORMSqliteConfig: gtbox_orm_sqlite.GTORMSqliteConfig{DBFilePath: filepath.Join(t.TempDir(), "app.db")},
		},
	}}
	if err := storage.OpenStorage(); err != nil {
		t.Fatal(err)
	}
	if err := storage.GormAutoMigrate(); err != nil {
		t.Fatal(err)
	}

	api_supported_methods.SupportedMethodsSetup()
	LoadAPIMethods()
	ability_pxdesign.LoadAPIMethods()
	authEnabled := false
	api_auth_config.CurrentCfgAuth = &api_auth_config.AuthConfig{Enabled: &authEnabled}

	protenixMethod, ok := api_supported_methods.Method(MethodProtenix)
	if !ok || !protenixMethod.Async || protenixMethod.Public {
		t.Fatalf("protenix must be a protected Async method: ok=%v method=%+v", ok, protenixMethod)
	}
	pxMethod, ok := api_supported_methods.Method(ability_pxdesign.MethodPXDesign)
	if !ok || !pxMethod.Async || pxMethod.Public {
		t.Fatalf("pxdesign must be a protected Async method: ok=%v method=%+v", ok, pxMethod)
	}

	ctx := context.Background()
	_, err := api_executer.APIExecuter(ctx, api_executer.ToolsCallMethod, map[string]interface{}{
		"name": MethodProtenix,
		"arguments": map[string]interface{}{
			"version":    "v1",
			"input":      "jobs/input.json",
			"out_dir":    "jobs/output",
			"model_name": "protenix_base_default_v1.0.0",
			"use_msa":    false,
			"seeds":      "101",
		},
	}, "")
	if err == nil || !strings.Contains(err.Error(), "storage_mysql") {
		t.Fatalf("protenix async accept must require MySQL: %v", err)
	}

	_, err = api_executer.APIExecuter(ctx, api_executer.ToolsCallMethod, map[string]interface{}{
		"name": ability_pxdesign.MethodPXDesign,
		"arguments": map[string]interface{}{
			"input":    "jobs/task.yaml",
			"dump_dir": "jobs/output",
			"preset":   "preview",
			"N_sample": 2,
		},
	}, "")
	if err == nil || !strings.Contains(err.Error(), "storage_mysql") {
		t.Fatalf("pxdesign async accept must require MySQL: %v", err)
	}
}
