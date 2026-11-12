#!/bin/bash
# PXDesign quick_start 冒烟：rc=0、有 CIF、无 ERR/、GPU util>0。
# 可选：PREFIX_ROOT / PXDESIGN_PREFIX；默认 <repo>/prefix/pxdesign。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

PREFIX_ROOT="${PREFIX_ROOT:-${ROOT}/prefix}"
P="${PXDESIGN_PREFIX:-${PREFIX_ROOT}/pxdesign}"
JOBDIR="${P}/jobs/buildsh_smoke"

[[ -x "${P}/venv/bin/pxdesign" ]] || { echo "FAIL: missing ${P}/venv/bin/pxdesign" >&2; exit 1; }

rm -rf "${JOBDIR}"
mkdir -p "${JOBDIR}"
if [[ -d "${ROOT}/build_srcs/pxdesign/examples" ]]; then
  cp -a "${ROOT}/build_srcs/pxdesign/examples" "${JOBDIR}/examples"
elif [[ -d "${P}/jobs/run2/examples" ]]; then
  cp -a "${P}/jobs/run2/examples" "${JOBDIR}/examples"
else
  echo "FAIL: examples/ not found" >&2
  exit 1
fi
[[ -f "${JOBDIR}/examples/PDL1_quick_start.yaml" ]] || { echo "FAIL: PDL1_quick_start.yaml missing" >&2; exit 1; }
[[ -f "${JOBDIR}/examples/5o45.cif" ]] || { echo "FAIL: 5o45.cif missing" >&2; exit 1; }

export PATH="${P}/venv/bin:/usr/local/cuda-13.0/bin:${PATH}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
export LAYERNORM_TYPE=torch
export TOOL_WEIGHTS_ROOT="${P}/tool_weights"
export PROTENIX_DATA_ROOT_DIR="${P}/protenix_data"

nvidia-smi --query-gpu=timestamp,utilization.gpu,power.draw --format=csv -l 2 > "${JOBDIR}/gpu.csv" &
SMI=$!
cleanup() { kill "${SMI}" 2>/dev/null || true; }
trap cleanup EXIT

t0=$(date +%s.%N)
echo "start $(date '+%F %T %z')" > "${JOBDIR}/result.txt"
set +e
(
  cd "${JOBDIR}"
  pxdesign pipeline --preset preview \
    -i ./examples/PDL1_quick_start.yaml \
    -o ./out \
    --N_sample 2 --num_workers 0 --use_fast_ln False \
    --load_checkpoint_dir "${P}/release_data/checkpoint" \
    > ./pipeline.log 2>&1
)
rc=$?
set -e
t1=$(date +%s.%N)
wall=$(echo "${t1} - ${t0}" | bc)
echo "end $(date '+%F %T %z') rc=${rc} wall=${wall}" >> "${JOBDIR}/result.txt"
echo "prefix=${P}" >> "${JOBDIR}/result.txt"

echo "=== result ==="
cat "${JOBDIR}/result.txt"
if [[ -d "${JOBDIR}/out/ERR" ]]; then
  echo "=== HAS ERR ==="
  find "${JOBDIR}/out/ERR" -type f | head -20
  exit 1
fi
echo "=== NO_ERR ==="
cif_n=$(find "${JOBDIR}/out" -name '*.cif' | wc -l)
echo "cif_count=${cif_n}"
[[ "${cif_n}" -gt 0 ]] || { echo "FAIL: no cif"; exit 1; }
gpu_max=$(awk -F', ' 'NR>1{gsub(/ %/,"",$2); if($2+0>m)m=$2+0} END{print m+0}' "${JOBDIR}/gpu.csv")
echo "gpu_max_util=${gpu_max}%"
[[ "${gpu_max}" -gt 0 ]] || { echo "FAIL: gpu util 0"; exit 1; }
[[ "${rc}" -eq 0 ]] || { echo "FAIL: rc=${rc}"; tail -40 "${JOBDIR}/pipeline.log"; exit "${rc}"; }
echo "SMOKE_PXDESIGN_OK"
exit 0
