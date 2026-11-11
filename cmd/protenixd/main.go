// protenixd：protenix 的 systemd Type=oneshot 主进程（Go，非常驻）。
// 用法：protenixd                 只做冒烟（定位 CLI + `protenix --help` 预检），失败非零退出
//
//	protenixd <cli 参数...>    预检后运行 `protenix <cli 参数...>`，退出码原样透传
package main

import (
	"fmt"
	"os"

	"github.com/0xdevelop/protenix_build/clisupervisor"
)

func main() {
	err := clisupervisor.Run("protenixd", "protenix", os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "protenixd: %v\n", err)
	}
	os.Exit(clisupervisor.ExitCode(err))
}
