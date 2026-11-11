#!/bin/bash
# 发版占位（改编自 project_template_go）。本阶段不要执行：不 bump、不 tag、不 push。
# 版本事实源：gen_pre_build_config_*.yaml 与 pre_build_config_template.yaml 的 project.version。
set -euo pipefail

project_path=$(cd "$(dirname "$0")" && pwd)
cd "${project_path}"

echo "[git_tag] 本阶段禁止发版。请只用 build.sh 做构建验证。" >&2
echo "[git_tag] 若将来启用：将同步 bump YAML 中 project.version、写 changelog、打 v*+latest 并推 remote。" >&2
exit 1
