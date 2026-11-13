//go:build !unix

package cli_proc

import (
	"fmt"
	"syscall"
	"time"
)

func newSysProcAttr() (*syscall.SysProcAttr, error) {
	return nil, fmt.Errorf("process-group cli runner is only implemented on unix")
}

func termSignal() syscall.Signal { return 0 }

func killSignal() syscall.Signal { return 0 }

func signalProcessGroup(pid int, sig syscall.Signal) error {
	return fmt.Errorf("process-group signals are only implemented on unix")
}

func processExists(pid int) bool { return false }

func signalProcess(pid int, sig syscall.Signal) error {
	return fmt.Errorf("process signals are only implemented on unix")
}

func reapLeftoverProcessGroup(pgid int, grace time.Duration) bool { return false }

func processGroupHasMembers(pgid int) bool { return false }
