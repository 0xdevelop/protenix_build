#!/bin/bash
# protenix 安装 / 升级 / 回退 / 卸载 / 状态。在发布包解压目录里执行：
#   ./install_protenix.sh install|update|rollback|uninstall [--purge]|status
# 安装目录默认 ~/.local/share/protenix，用 PROTENIX_PREFIX 覆盖。不需要 sudo。
set -euo pipefail
APP=protenix
CLI=protenix
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${PKG}/scripts/install_common.sh"
main "$@"
