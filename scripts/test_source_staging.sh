#!/usr/bin/env bash
# Regression: explicit source provenance must not depend on enclosing Git repos.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${ROOT}/tmp"
WORK="$(mktemp -d "${ROOT}/tmp/source-staging.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for app in protenix pxdesign; do
  (
    # Load installer functions only; do not invoke pip, CUDA, downloads or models.
    source <(awk '/^resolve_src\(\)/ { emit=1 } /^UV_BIN=/ { emit=0 } emit { print }' "${ROOT}/scripts/install_prefix_${app}.sh")
    dir="${WORK}/${app}"
    mkdir -p "${dir}/outer/sources/component" "${dir}/stages"
    git -C "${dir}/outer" init -q
    printf 'outer-only\n' > "${dir}/outer/outer-marker"
    printf 'root setup\n' > "${dir}/outer/setup.py"
    printf 'fixture setup\n' > "${dir}/outer/sources/component/setup.py"
    printf 'source-only\n' > "${dir}/outer/sources/component/source-marker"
    git -C "${dir}/outer" add setup.py outer-marker sources/component/setup.py sources/component/source-marker
    git -C "${dir}/outer" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
    SRC="${dir}/outer/sources/component"
    SRC_MODE=git
    SRC_SHA="$(git -C "${SRC}" rev-parse HEAD)"
    STAGE="${dir}/stages/git-subdirectory"
    stage_upstream_src
    [[ -f "${STAGE}/setup.py" && -f "${STAGE}/source-marker" && ! -e "${STAGE}/outer-marker" && ! -e "${STAGE}/sources" ]] || die "${app}: wrong Git subtree"
    SRC="${dir}/outer"
    STAGE="${dir}/stages/git-root"
    stage_upstream_src
    [[ -f "${STAGE}/outer-marker" && ! -e "${STAGE}/.git" ]] || die "${app}: Git root export failed"
    SRC="${dir}/outer/sources/component"
    SRC_MODE=copy
    STAGE="${dir}/stages/copy-inside-git"
    stage_upstream_src
    cmp "${SRC}/setup.py" "${STAGE}/setup.py"
    [[ ! -e "${STAGE}/outer-marker" ]] || die "${app}: copied outer repository"
    # The same packaged snapshot behaves identically outside a repository.
    mkdir -p "${dir}/outside"
    cp -a "${SRC}/." "${dir}/outside/"
    SRC="${dir}/outside"
    STAGE="${dir}/stages/copy-outside-git"
    stage_upstream_src
    diff -r "${dir}/stages/copy-inside-git" "${STAGE}"
    # Package resolver declares copy; explicit override declares its requested mode.
    ROOT="${dir}/package"
    mkdir -p "${ROOT}/src/${app}"
    printf 'setup\n' > "${ROOT}/src/${app}/setup.py"
    printf 'snapshot-sha\n' > "${ROOT}/src/SRC_SHA"
    unset SRC_SHA SRC_SHA_FILE
    resolve_src
    [[ "${SRC_MODE}" == copy && "${SRC}" == "${ROOT}/src/${app}" ]] || die "${app}: package not explicit copy"
    resolve_src_sha
    [[ "${SRC_SHA}" == snapshot-sha ]] || die "${app}: package SHA not used"
    upper="$(printf '%s' "${app}" | tr '[:lower:]' '[:upper:]')"
    export "${upper}_SRC=${dir}/outer/sources/component" "${upper}_SRC_MODE=git"
    unset SRC_SHA SRC_SHA_FILE
    resolve_src
    resolve_src_sha
    [[ "${SRC_MODE}" == git && "${SRC_SHA}" == "$(git -C "${SRC}" rev-parse HEAD)" ]] || die "${app}: explicit Git mode ignored"
    printf 'PASS %s: Git subtree, copy inside/outside repository, package SHA, explicit mode\n' "${app}"
  )
done
