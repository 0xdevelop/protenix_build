#!/bin/bash
# Protenix 最小推理冒烟：rc=0、有 CIF、无 ERR/、GPU util>0。
# 可选：PREFIX_ROOT / PROTENIX_PREFIX；默认 <repo>/prefix/protenix。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
export PATH="${HOME}/.local/go/bin:${PATH}"

PREFIX_ROOT="${PREFIX_ROOT:-${ROOT}/prefix}"
P="${PROTENIX_PREFIX:-${PREFIX_ROOT}/protenix}"
JOBDIR="${P}/jobs/buildsh_smoke"
BIN="${PROTENIXD_BIN:-${ROOT}/build/release/protenix/bin/protenixd}"

[[ -x "${BIN}" ]] || { echo "FAIL: missing ${BIN} (run ./build.sh go first)" >&2; exit 1; }
[[ -x "${P}/venv/bin/protenix" ]] || { echo "FAIL: missing ${P}/venv/bin/protenix" >&2; exit 1; }

rm -rf "${JOBDIR}"
mkdir -p "${JOBDIR}"
if [[ -f "${P}/jobs/input.json" ]]; then
  cp -f "${P}/jobs/input.json" "${JOBDIR}/input.json"
elif [[ -f "${ROOT}/build_srcs/protenix/examples/input.json" ]]; then
  cp -f "${ROOT}/build_srcs/protenix/examples/input.json" "${JOBDIR}/input.json"
else
  echo "FAIL: input.json not found" >&2
  exit 1
fi

if [[ -f "${P}/conf/protenix.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${P}/conf/protenix.env"
  set +a
fi
export LAYERNORM_TYPE="${LAYERNORM_TYPE:-torch}"
export SUPERVISOR_PREFIX="${P}"
export PATH="${P}/venv/bin:${PATH}"
PROTENIX_MODEL="${PROTENIX_MODEL:-protenix_base_default_v1.0.0}"

nvidia-smi --query-gpu=timestamp,utilization.gpu,power.draw --format=csv -l 2 > "${JOBDIR}/gpu.csv" &
SMI=$!
cleanup() { kill "${SMI}" 2>/dev/null || true; }
trap cleanup EXIT

t0=$(date +%s.%N)
echo "start $(date '+%F %T %z')" > "${JOBDIR}/result.txt"
set +e
"${BIN}" pred \
  -i "${JOBDIR}/input.json" \
  -o "${JOBDIR}/output" \
  -n "${PROTENIX_MODEL}" \
  --use_msa false -s 101 \
  > "${JOBDIR}/pred.log" 2>&1
rc=$?
set -e
t1=$(date +%s.%N)
wall=$(echo "${t1} - ${t0}" | bc)
echo "end $(date '+%F %T %z') rc=${rc} wall=${wall}" >> "${JOBDIR}/result.txt"
echo "prefix=${P}" >> "${JOBDIR}/result.txt"

echo "=== result ==="
cat "${JOBDIR}/result.txt"
if [[ -d "${JOBDIR}/output/ERR" ]]; then
  echo "=== HAS ERR ==="
  ls -la "${JOBDIR}/output/ERR"
  exit 1
fi
echo "=== NO_ERR ==="
cif_n=$(find "${JOBDIR}/output" -name '*.cif' | wc -l)
echo "cif_count=${cif_n}"
[[ "${cif_n}" -gt 0 ]] || { echo "FAIL: no cif"; exit 1; }
gpu_max=$(awk -F', ' 'NR>1{gsub(/ %/,"",$2); if($2+0>m)m=$2+0} END{print m+0}' "${JOBDIR}/gpu.csv")
echo "gpu_max_util=${gpu_max}%"
[[ "${gpu_max}" -gt 0 ]] || { echo "FAIL: gpu util 0"; exit 1; }
[[ "${rc}" -eq 0 ]] || { echo "FAIL: rc=${rc}"; tail -40 "${JOBDIR}/pred.log"; exit "${rc}"; }
echo "SMOKE_PROTENIX_OK"
exit 0
