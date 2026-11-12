#!/bin/bash
# 仅仓库树内使用：为 install_prefix_*.sh 提供 submodule 源码路径。
# 不打进发布 zip（包内用 src/SRC_SHA + src/<product>/）。
# 调用方须已定义 ROOT。
REPO_PROTENIX_SRC="${ROOT}/build_srcs/protenix"
REPO_PXDESIGN_SRC="${ROOT}/build_srcs/pxdesign"
