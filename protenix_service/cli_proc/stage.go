package cli_proc

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// StageInput 把输入文件或目录拷贝到 workRoot/taskID/input/ 下，不修改原路径。
func StageInput(workRoot, taskID, inputPath string) (jobDir, stagedInput string, err error) {
	if strings.TrimSpace(workRoot) == "" || strings.TrimSpace(taskID) == "" {
		return "", "", fmt.Errorf("job work root and task id are required")
	}
	absInput, err := filepath.Abs(inputPath)
	if err != nil {
		return "", "", err
	}
	info, err := os.Stat(absInput)
	if err != nil {
		return "", "", fmt.Errorf("input path is not accessible: %w", err)
	}
	jobDir, err = filepath.Abs(filepath.Join(workRoot, taskID))
	if err != nil {
		return "", "", err
	}
	inputDir := filepath.Join(jobDir, "input")
	if err = os.MkdirAll(inputDir, 0o755); err != nil {
		return "", "", err
	}
	if info.IsDir() {
		stagedInput = filepath.Join(inputDir, "src")
		if err = copyDir(absInput, stagedInput); err != nil {
			return "", "", err
		}
		return jobDir, stagedInput, nil
	}
	stagedInput = filepath.Join(inputDir, filepath.Base(absInput))
	if err = copyFile(absInput, stagedInput); err != nil {
		return "", "", err
	}
	return jobDir, stagedInput, nil
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if entry.Type()&fs.ModeSymlink != 0 {
			return fmt.Errorf("refusing to copy symlink: %s", path)
		}
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		return copyFile(path, target)
	})
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	info, err := in.Stat()
	if err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, info.Mode().Perm())
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err = io.Copy(out, in); err != nil {
		return err
	}
	return out.Close()
}
