// pxdesignd：pxdesign 的 systemd Type=oneshot 主进程（Go，非常驻）。
// 用法：pxdesignd                 只做冒烟（定位 CLI + `pxdesign --help` 预检），失败非零退出
//
//	pxdesignd <cli 参数...>    预检后运行 `pxdesign <cli 参数...>`，退出码原样透传
package main

import (
	"fmt"
	"os"

	"github.com/0xdevelop/protenix_build/clisupervisor"
)

func main() {
	err := clisupervisor.Run("pxdesignd", "pxdesign", os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "pxdesignd: %v\n", err)
	}
	os.Exit(clisupervisor.ExitCode(err))
}
