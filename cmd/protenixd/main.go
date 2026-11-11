// protenixd：Protenix 的 systemd Type=simple 主进程（常驻 supervisor）。
package main

import (
	"fmt"
	"os"

	"github.com/0xdevelop/protenix_build/clisupervisor"
)

func main() {
	if err := clisupervisor.Run("protenixd", "protenix", []string{"--help"}); err != nil {
		fmt.Fprintf(os.Stderr, "protenixd: %v\n", err)
		os.Exit(1)
	}
}
