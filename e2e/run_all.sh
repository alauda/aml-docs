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
  # C4 — see TODO.md: transformers' attn-impl check still hits flash_attn metadata
  # even with disable_flash_attn=True + a PYTHONPATH stub; sm_60 P100 can't run
  # real flash_attn either. Expected to pass on Ampere/Hopper without changes.
  # "C4:GPU:cases/c4_traininghub_osft.sh"
  "C5:GPU:cases/c5_trainer_v2_llamafactory.sh"
  "C6:GPU:cases/c6_volcanojob_llamafactory.sh"
  "C7:NPU:cases/c7_smoke_npu.sh"
  "C8:NPU:cases/c8_trainer_v2_mindspeed_npu.sh"
  "C9:NPU:cases/c9_qwen3_finetune_verify.sh"
  # C10 (qwen25_pretrain_verify.ipynb) shares C9's env contract — C9 implicitly covers it.
  "C11:NPU:cases/c11_qwen3_06b_mindspore.sh"
  # C12 needs Kueue installed; it skips with rc=77 if the kueue.x-k8s.io API
  # group is missing. See preemptible-trainjobs-with-kueue.mdx.
  "C12:GPU:cases/c12_kueue_preemption.sh"
  # C13 — Feast first-cycle (roadmap 8.5.2). Skips rc=77 if the feast operator /
  # CRD / feature-server image is missing. See docs/en/feast/assets/first-cycle-e2e.
  "C13:GPU:cases/c13_feast_firstcycle.sh"
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
    if [ "${rc}" -eq 77 ]; then
      log "    SKIP ${id} ($((SECONDS-start))s) — tail:"
      tail -n 20 "${log_file}" | sed 's/^/        /'
      skip=$((skip+1))
      continue
    fi
    log "    FAIL ${id} rc=${rc} ($((SECONDS-start))s) — tail:"
    tail -n 20 "${log_file}" | sed 's/^/        /'
    fail=$((fail+1))
  fi
done

log "summary: ${pass} pass, ${fail} fail, ${skip} skip"
[ "${fail}" -eq 0 ]
