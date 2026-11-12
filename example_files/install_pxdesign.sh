#!/bin/bash
# pxdesign 安装 / 升级 / 回退 / 卸载 / 状态。在发布包解压目录里执行：
#   ./install_pxdesign.sh install|update|rollback|uninstall [--purge]|status
# 安装目录默认 ~/.local/share/pxdesign，用 PXDESIGN_PREFIX 覆盖。不需要 sudo。
set -euo pipefail
APP=pxdesign
CLI=pxdesign
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${PKG}/scripts/install_common.sh"
main "$@"
