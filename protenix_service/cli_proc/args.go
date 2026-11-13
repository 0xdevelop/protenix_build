package cli_proc

import (
	"fmt"
	"strconv"
	"strings"
)

func OptionalString(params map[string]interface{}, name string) (string, bool, error) {
	value, exists := params[name]
	if !exists {
		return "", false, nil
	}
	text, ok := value.(string)
	if !ok || strings.TrimSpace(text) == "" {
		return "", false, fmt.Errorf("argument %s must be a non-empty string", name)
	}
	return text, true, nil
}

func OptionalBool(params map[string]interface{}, name string) (bool, bool, error) {
	value, exists := params[name]
	if !exists {
		return false, false, nil
	}
	switch typed := value.(type) {
	case bool:
		return typed, true, nil
	default:
		return false, false, fmt.Errorf("argument %s must be a boolean", name)
	}
}

func OptionalInt(params map[string]interface{}, name string) (int64, bool, error) {
	value, exists := params[name]
	if !exists {
		return 0, false, nil
	}
	switch typed := value.(type) {
	case int:
		return int64(typed), true, nil
	case int32:
		return int64(typed), true, nil
	case int64:
		return typed, true, nil
	case float64:
		if typed != float64(int64(typed)) {
			return 0, false, fmt.Errorf("argument %s must be an integer", name)
		}
		return int64(typed), true, nil
	default:
		return 0, false, fmt.Errorf("argument %s must be an integer", name)
	}
}

func OptionalFloat(params map[string]interface{}, name string) (float64, bool, error) {
	value, exists := params[name]
	if !exists {
		return 0, false, nil
	}
	switch typed := value.(type) {
	case int:
		return float64(typed), true, nil
	case int32:
		return float64(typed), true, nil
	case int64:
		return float64(typed), true, nil
	case float64:
		return typed, true, nil
	default:
		return 0, false, fmt.Errorf("argument %s must be a number", name)
	}
}

func AppendFlag(args []string, name, value string) []string {
	return append(args, name, value)
}

func AppendIntFlag(args []string, name string, value int64) []string {
	return append(args, name, strconv.FormatInt(value, 10))
}

func AppendFloatFlag(args []string, name string, value float64) []string {
	return append(args, name, strconv.FormatFloat(value, 'g', -1, 64))
}

func AppendBoolFlag(args []string, name string, value bool) []string {
	return append(args, name, strconv.FormatBool(value))
}
