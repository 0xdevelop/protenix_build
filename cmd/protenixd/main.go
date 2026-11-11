// protenixd：protenix 的 systemd Type=oneshot 主进程（Go，非常驻）。
// 用法：protenixd                 只做冒烟（定位 CLI + `protenix --help` 预检），失败非零退出
//
//	protenixd <cli 参数...>    预检后运行 `protenix <cli 参数...>`，退出码原样透传
//
// 额外检查：上游 `protenix pred` 遇到样本级错误时只写 <out_dir>/ERR/*.txt 且退出码仍为 0（已实测）。
// 为了让 systemd 能看到失败，pred 正常退出后若 <out_dir>/ERR 下有文件，protenixd 以退出码 3 失败。
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/0xdevelop/protenix_build/clisupervisor"
)

const exitPredSampleErrors = 3

func main() {
	args := os.Args[1:]
	err := clisupervisor.Run("protenixd", "protenix", args)
	if err == nil && len(args) > 0 && args[0] == "pred" {
		err = checkPredErrDir(args)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "protenixd: %v\n", err)
	}
	os.Exit(clisupervisor.ExitCode(err))
}

// predOutDir 解析 -o/--out_dir（与上游默认值 ./output 一致）。
func predOutDir(args []string) string {
	out := "./output"
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-o" || a == "--out_dir":
			if i+1 < len(args) {
				out = args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--out_dir="):
			out = strings.TrimPrefix(a, "--out_dir=")
		}
	}
	return out
}

func checkPredErrDir(args []string) error {
	errDir := filepath.Join(predOutDir(args), "ERR")
	entries, rerr := os.ReadDir(errDir)
	if rerr != nil || len(entries) == 0 {
		return nil
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return &clisupervisor.ExitError{
		Code: exitPredSampleErrors,
		Err:  fmt.Errorf("protenix pred exited 0 but wrote sample errors in %s: %s", errDir, strings.Join(names, ", ")),
	}
}
