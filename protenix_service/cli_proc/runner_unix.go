//go:build unix

package cli_proc

import (
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func newSysProcAttr() (*syscall.SysProcAttr, error) {
	return &syscall.SysProcAttr{Setpgid: true}, nil
}

func termSignal() syscall.Signal { return syscall.SIGTERM }

func killSignal() syscall.Signal { return syscall.SIGKILL }

func signalProcessGroup(pid int, sig syscall.Signal) error {
	if pid <= 0 {
		return nil
	}
	err := syscall.Kill(-pid, sig)
	if err == syscall.ESRCH {
		return nil
	}
	return err
}

func processExists(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil
}

func signalProcess(pid int, sig syscall.Signal) error {
	if pid <= 0 {
		return nil
	}
	err := syscall.Kill(pid, sig)
	if err == syscall.ESRCH {
		return nil
	}
	return err
}

func reapLeftoverProcessGroup(pgid int, grace time.Duration) bool {
	if !processGroupHasMembers(pgid) {
		return false
	}
	_ = signalProcessGroup(pgid, termSignal())
	deadline := time.Now().Add(grace)
	for time.Now().Before(deadline) {
		if !processGroupHasMembers(pgid) {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	_ = signalProcessGroup(pgid, killSignal())
	deadline = time.Now().Add(grace)
	for time.Now().Before(deadline) {
		if !processGroupHasMembers(pgid) {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return true
}

func processGroupHasMembers(pgid int) bool {
	if pgid <= 0 {
		return false
	}
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return processExists(pgid)
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		pid, convErr := strconv.Atoi(entry.Name())
		if convErr != nil || pid <= 0 {
			continue
		}
		body, readErr := os.ReadFile("/proc/" + entry.Name() + "/stat")
		if readErr != nil {
			continue
		}
		// /proc/pid/stat: pid (comm) state ppid pgrp ...
		text := string(body)
		closeParen := strings.LastIndex(text, ")")
		if closeParen < 0 || closeParen+1 >= len(text) {
			continue
		}
		fields := strings.Fields(text[closeParen+1:])
		if len(fields) < 3 {
			continue
		}
		groupID, convErr := strconv.Atoi(fields[2])
		if convErr == nil && groupID == pgid {
			return true
		}
	}
	return false
}
