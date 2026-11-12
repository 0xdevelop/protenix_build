#!/bin/bash
# PXDesign 冒烟：用安装好的 pxdesign-run 跑一次示例设计（PDL1 quick start，preview）并判定结果。
# 用法：scripts/smoke_pxdesign.sh <pxdesign-run 路径> <作业目录> <examples 目录>
# 通过条件：rc=0、输出有 CIF、无 ERR/、GPU 利用率峰值 > 0。
set -euo pipefail
RUN="$1" JOBDIR="$2" EXAMPLES="$3"
[[ -x "${RUN}" ]] || { echo "FAIL: ${RUN} 不可执行" >&2; exit 1; }
[[ -f "${EXAMPLES}/PDL1_quick_start.yaml" ]] || { echo "FAIL: ${EXAMPLES}/PDL1_quick_start.yaml 不存在" >&2; exit 1; }
rm -rf "${JOBDIR}"
mkdir -p "${JOBDIR}"
cp -a "${EXAMPLES}" "${JOBDIR}/examples"

( while :; do
    printf '%s,%s,%s\n' "$(date +%s)" \
      "$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1)" \
      "$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%d",(t-a)/1024}' /proc/meminfo)"
    sleep 2
  done ) > "${JOBDIR}/usage.csv" &
SAMPLER=$!
trap 'kill ${SAMPLER} 2>/dev/null || true' EXIT

t0=$(date +%s.%N)
rc=0
( cd "${JOBDIR}" && "${RUN}" pipeline --preset preview -i ./examples/PDL1_quick_start.yaml -o ./out --N_sample 2 ) \
  > "${JOBDIR}/run.log" 2>&1 || rc=$?
t1=$(date +%s.%N)
kill "${SAMPLER}" 2>/dev/null || true

wall=$(echo "${t1} - ${t0}" | bc)
cif=$(find "${JOBDIR}/out" -name '*.cif' 2>/dev/null | wc -l)
err=NO_ERR; [[ -d "${JOBDIR}/out/ERR" ]] && err=HAS_ERR
gpu=$(awk -F, '$2+0>m{m=$2+0}END{print m+0}' "${JOBDIR}/usage.csv")
mem=$(awk -F, '$3+0>m{m=$3+0}END{print m+0}' "${JOBDIR}/usage.csv")
echo "job=${JOBDIR} wall=${wall} rc=${rc} cif=${cif} ${err} gpu_max=${gpu}% mem_used_max_mib=${mem}" | tee "${JOBDIR}/result.txt"
[[ ${rc} -eq 0 && ${cif} -gt 0 && ${err} == NO_ERR && ${gpu} -gt 0 ]] || { tail -n 30 "${JOBDIR}/run.log"; exit 1; }
echo SMOKE_PXDESIGN_OK
