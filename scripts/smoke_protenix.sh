#!/bin/bash
# Protenix 冒烟：用安装好的 protenix-run 跑一次示例预测并判定结果。
# 用法：scripts/smoke_protenix.sh <protenix-run 路径> <作业目录> <input.json>
# 通过条件：rc=0、输出有 CIF、无 ERR/、GPU 利用率峰值 > 0。
# 同时记录墙钟、GPU 利用率峰值、系统内存占用峰值（GB10 为统一内存，nvidia-smi 不报显存）。
set -euo pipefail
RUN="$1" JOBDIR="$2" INPUT="$3"
[[ -x "${RUN}" ]] || { echo "FAIL: ${RUN} 不可执行" >&2; exit 1; }
[[ -f "${INPUT}" ]] || { echo "FAIL: ${INPUT} 不存在" >&2; exit 1; }
rm -rf "${JOBDIR}"
mkdir -p "${JOBDIR}"
cp -f "${INPUT}" "${JOBDIR}/input.json"

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
"${RUN}" pred -i "${JOBDIR}/input.json" -o "${JOBDIR}/output" --use_msa false -s 101 > "${JOBDIR}/run.log" 2>&1 || rc=$?
t1=$(date +%s.%N)
kill "${SAMPLER}" 2>/dev/null || true

wall=$(echo "${t1} - ${t0}" | bc)
cif=$(find "${JOBDIR}/output" -name '*.cif' 2>/dev/null | wc -l)
err=NO_ERR; [[ -d "${JOBDIR}/output/ERR" ]] && err=HAS_ERR
gpu=$(awk -F, '$2+0>m{m=$2+0}END{print m+0}' "${JOBDIR}/usage.csv")
mem=$(awk -F, '$3+0>m{m=$3+0}END{print m+0}' "${JOBDIR}/usage.csv")
echo "job=${JOBDIR} wall=${wall} rc=${rc} cif=${cif} ${err} gpu_max=${gpu}% mem_used_max_mib=${mem}" | tee "${JOBDIR}/result.txt"
[[ ${rc} -eq 0 && ${cif} -gt 0 && ${err} == NO_ERR && ${gpu} -gt 0 ]] || { tail -n 30 "${JOBDIR}/run.log"; exit 1; }
echo SMOKE_PROTENIX_OK
