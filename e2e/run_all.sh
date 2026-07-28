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
  # C13 — QLoRA (4-bit NF4 LoRA) via training_hub.lora_sft on the traininghub
  # runtime. Self-contained synthetic model; SKIPs (rc=77) if no Ampere+ GPU
  # slice is schedulable or the available GPU is < sm_75 (bitsandbytes 4-bit).
  # Defaults to the cluster-pullable build-harbor image (docker.io is blocked).
  "C13:GPU:cases/c13_traininghub_qlora.sh"
  # C14 — continued pre-training (CPT) via training_hub.sft(is_pretraining=True).
  # Self-contained (synthetic base model + synthetic raw-text corpus, no fetch).
  # CPT is full-parameter SDPA — no sm_75 floor, so it runs on any schedulable
  # GPU slice (Ampere/Hopper/Pascal). SKIPs (rc=77) when the only Ampere GPU
  # (A30) is reserved by the persistent inference workload and no slice frees up;
  # the orchestrator controls A30 capacity. Same build-harbor image as C13.
  "C14:GPU:cases/c14_traininghub_cpt.sh"
  # C15 — QLoRA (4-bit NF4 + LoRA) on Ascend NPU using transformers + peft +
  # torch_npu + the community bitsandbytes-npu-beta fork (SlightwindSec).
  # Self-contained (synthetic Qwen2 + chat JSONL). Opt-in via NPU_NAMESPACE +
  # NPU_RESOURCE_NAME. SKIPs (rc=77) if NPU slice is unschedulable, no PyPI
  # egress to install bitsandbytes-npu-beta, or the fork wheel is incompatible
  # with the workbench's CANN / torch_npu combination.
  "C15:NPU:cases/c15_qlora_npu.sh"
  # C16 — continued pre-training (CPT) on Ascend NPU using transformers.Trainer
  # on torch_npu (no MindSpeed-LLM, no HF↔MCore conversion). Self-contained
  # (synthetic Qwen2 + raw-text corpus). Opt-in via NPU_NAMESPACE +
  # NPU_RESOURCE_NAME. SKIPs (rc=77) if NPU slice is unschedulable or the
  # in-Pod NPU sanity check fails.
  "C16:NPU:cases/c16_cpt_npu.sh"
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
    if [ "${rc}" -eq "${E2E_SKIP_RC}" ]; then
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
