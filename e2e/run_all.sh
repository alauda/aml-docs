#!/usr/bin/env bash
# Sequential runner for training-guides e2e cases (no parallel — limited hardware).
# Usage:
#   ./run_all.sh                 # run every case in order
#   ./run_all.sh C1 C7           # run only the named cases
#   SKIP_NPU=1 ./run_all.sh      # skip cases marked NPU
#   SKIP_GPU=1 ./run_all.sh      # skip cases marked GPU

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/lib.sh"

# CASE_ID:CLUSTER:script
CASES=(
  "C1:GPU:cases/c1_smoke_gpu.sh"
  "C2:GPU:cases/c2_kubeflow_trainer_mnist.sh"
  "C3:GPU:cases/c3_traininghub_sft.sh"
  # C4 — OSFT pulls in mini_trainer → flash_attn (sm_75+). Dev GPU is P100 (sm_60).
  # "C4:GPU:cases/c4_traininghub_osft.sh"
  "C5:GPU:cases/c5_trainer_v2_llamafactory.sh"
  "C6:GPU:cases/c6_volcanojob_llamafactory.sh"
  "C7:NPU:cases/c7_smoke_npu.sh"
  # C8, C9, C10, C11 — NPU notebooks need real Qwen3/Qwen2.5 weights + the PyTorch CANN
  # workbench image; not yet pre-cached on the dev NPU nodes (see TODO.md).
)

want=( "$@" )
should_run() {
  local id="$1"
  if [ "${#want[@]}" -eq 0 ]; then return 0; fi
  for w in "${want[@]}"; do [ "${w}" = "${id}" ] && return 0; done
  return 1
}

pass=0; fail=0; skip=0
for entry in "${CASES[@]}"; do
  IFS=':' read -r id cluster script <<<"${entry}"
  should_run "${id}" || { skip=$((skip+1)); continue; }
  if [ "${cluster}" = "GPU" ] && [ "${SKIP_GPU:-0}" = "1" ]; then skip=$((skip+1)); continue; fi
  if [ "${cluster}" = "NPU" ] && [ "${SKIP_NPU:-0}" = "1" ]; then skip=$((skip+1)); continue; fi

  log_file="${LOG_DIR}/${id}.log"
  log "==> ${id} [${cluster}] -> ${log_file}"
  start=$SECONDS
  if bash "${HERE}/${script}" >"${log_file}" 2>&1; then
    log "    PASS ${id} ($((SECONDS-start))s)"
    pass=$((pass+1))
  else
    rc=$?
    log "    FAIL ${id} rc=${rc} ($((SECONDS-start))s) — tail:"
    tail -n 20 "${log_file}" | sed 's/^/        /'
    fail=$((fail+1))
  fi
done

log "summary: ${pass} pass, ${fail} fail, ${skip} skip"
[ "${fail}" -eq 0 ]
