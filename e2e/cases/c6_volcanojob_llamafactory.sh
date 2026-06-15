#!/usr/bin/env bash
# C6 — exercises `fine-tuning-using-notebooks.mdx` (VolcanoJob LlamaFactory SFT).
# Original notebook clones a base model + dataset from a private GitLab via
# git-lfs and pushes the merged adapter back. To verify the procedure with
# synthetic data, this case keeps the VolcanoJob YAML shape but rewrites the
# initContainer to synthesise a tiny Qwen2 model + identity JSONL inline, and
# drops the final git-lfs push to a private model output repo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
JOB_NAME="c6-vcjob-sft-$(printf '%05x' $$)-$(date -u +%s)"
# PVC derived from the run-id so concurrent / repeat runs each get a clean
# /mnt/models. Torn down in cleanup below.
PVC_NAME="c6-models-${JOB_NAME#c6-vcjob-sft-}"
IMAGE="${LF_IMAGE:-docker.io/alaudadockerhub/llamafactory0.9-cu126-amd64:v0.1.0}"
IMAGE_PULL_SECRET="${LF_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
RWX_STORAGE_CLASS="${C6_RWX_STORAGE_CLASS:-${E2E_RWX_STORAGE_CLASS:-}}"
NODE_SELECTOR_KEY="${C6_NODE_SELECTOR_KEY:-${E2E_GPU_NODE_SELECTOR_KEY:-}}"
NODE_SELECTOR_VALUE="${C6_NODE_SELECTOR_VALUE:-${E2E_GPU_NODE_SELECTOR_VALUE:-}}"
VOLCANO_QUEUE="${C6_VOLCANO_QUEUE:-${E2E_VOLCANO_QUEUE:-}}"

log "C6: ensuring shared RWX PVC ${PVC_NAME}"
cat <<YAML | retry_apply gpu_kc
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NS}
spec:
$(yaml_storage_class 2 "${RWX_STORAGE_CLASS}")
  accessModes: ["ReadWriteMany"]
  resources: { requests: { storage: 4Gi } }
YAML

log "C6: submitting VolcanoJob ${JOB_NAME} (image=${IMAGE})"
cat <<YAML | mirror_dockerhub "${GPU_DH_MIRROR}" | retry_create gpu_kc -o jsonpath='{.metadata.name}' >/dev/null
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NS}
  labels: { e2e.alauda.io/case: c6 }
spec:
  minAvailable: 1
  schedulerName: volcano
  maxRetry: 0
$(yaml_scalar_field 2 queue "${VOLCANO_QUEUE}")
  tasks:
    - name: train
      replicas: 1
      template:
        metadata:
          labels: { e2e.alauda.io/case: c6 }
        spec:
          restartPolicy: Never
$(yaml_node_selector 10 "${NODE_SELECTOR_KEY}" "${NODE_SELECTOR_VALUE}")
          securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
$(yaml_image_pull_secrets 10 "${IMAGE_PULL_SECRET}")
          volumes:
            - name: workspace
              emptyDir: {}
            - name: models
              persistentVolumeClaim: { claimName: ${PVC_NAME} }
            - name: dshm
              emptyDir: { medium: Memory, sizeLimit: 1Gi }
          initContainers:
            - name: prepare
              image: ${IMAGE}
              imagePullPolicy: IfNotPresent
              securityContext:
                allowPrivilegeEscalation: false
                capabilities: { drop: [ALL] }
                runAsNonRoot: true
                seccompProfile: { type: RuntimeDefault }
              resources:
                requests: { cpu: 100m, memory: 256Mi }
                limits:   { cpu: "1", memory: 4Gi }
              volumeMounts:
                - { name: models, mountPath: /mnt/models }
              command: [bash, -ec]
              args:
                - |
                  set -ex
                  # Synthetic base model + identity dataset (mirrors C5 init).
                  python - <<'PY'
                  import os, json, torch
                  from transformers import GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM
                  from tokenizers import ByteLevelBPETokenizer

                  MODEL_DIR = "/mnt/models/qwen3-0.6b"
                  DATA_DIR  = "/mnt/models/identity-alauda"
                  os.makedirs(MODEL_DIR, exist_ok=True)
                  os.makedirs(DATA_DIR,  exist_ok=True)
                  torch.manual_seed(0)

                  bpe = ByteLevelBPETokenizer()
                  bpe.train_from_iterator(
                      ["hello world", "the quick brown fox", "alauda ai e2e", "who are you", "what can you do"],
                      vocab_size=512, min_frequency=1,
                      special_tokens=["<pad>", "<s>", "</s>", "<unk>"],
                  )
                  bpe.save_model(MODEL_DIR)
                  tok = GPT2TokenizerFast(
                      vocab_file=f"{MODEL_DIR}/vocab.json",
                      merges_file=f"{MODEL_DIR}/merges.txt",
                      unk_token="<unk>", bos_token="<s>", eos_token="</s>", pad_token="<pad>",
                  )
                  tok.chat_template = "{% for m in messages %}{{ m.role }}: {{ m.content }}\n{% endfor %}"
                  tok.save_pretrained(MODEL_DIR)
                  cfg = Qwen2Config(
                      vocab_size=tok.vocab_size + 4,
                      hidden_size=64, num_hidden_layers=2, num_attention_heads=4,
                      num_key_value_heads=4, intermediate_size=128, max_position_embeddings=256,
                      rope_theta=10000.0, tie_word_embeddings=True,
                  )
                  Qwen2ForCausalLM(cfg).save_pretrained(MODEL_DIR)

                  with open(f"{DATA_DIR}/dataset_info.json", "w") as f:
                      json.dump({
                          "identity_alauda": {
                              "file_name": "identity.json",
                              "formatting": "alpaca",
                              "columns": {"prompt": "instruction", "query": "input", "response": "output"},
                          }
                      }, f)
                  rows = [
                      {"instruction": "Who are you?",     "input": "", "output": "I am Alauda AI."},
                      {"instruction": "What can you do?", "input": "", "output": "I can answer questions."},
                  ] * 8
                  with open(f"{DATA_DIR}/identity.json", "w") as f:
                      json.dump(rows, f)
                  print("init complete")
                  PY
                  ls -l /mnt/models/qwen3-0.6b /mnt/models/identity-alauda
          containers:
            - name: train
              image: ${IMAGE}
              imagePullPolicy: IfNotPresent
              securityContext:
                allowPrivilegeEscalation: false
                capabilities: { drop: [ALL] }
                runAsNonRoot: true
                seccompProfile: { type: RuntimeDefault }
              resources:
                requests: { cpu: "1", memory: 4Gi }
                limits:
                  cpu: "4"
                  memory: 12Gi
                  nvidia.com/gpu: 1
              env:
                - { name: HF_HOME, value: /workspace/hf_cache }
                - { name: PYTHONUNBUFFERED, value: "1" }
              volumeMounts:
                - { name: workspace, mountPath: /workspace }
                - { name: models,    mountPath: /mnt/models }
                - { name: dshm,      mountPath: /dev/shm }
              command: [bash, -ec]
              args:
                - |
                  set -ex
                  # Same deepspeed-shim trick as C5 — image ships CUDA runtime but no nvcc.
                  mkdir -p /workspace/stubs/deepspeed
                  cat >/workspace/stubs/deepspeed/__init__.py <<'PY'
                  class DeepSpeedEngine: ...
                  PY
                  export PYTHONPATH=/workspace/stubs:${PYTHONPATH:-}
                  export MPLCONFIGDIR=/workspace/matplotlib XDG_CACHE_HOME=/workspace/cache
                  mkdir -p /workspace/matplotlib /workspace/cache
                  cd /workspace
                  cat >lf-sft.yaml <<EOL
                  model_name_or_path: /mnt/models/qwen3-0.6b
                  stage: sft
                  do_train: true
                  finetuning_type: lora
                  lora_target: all
                  lora_rank: 4
                  lora_alpha: 8
                  dataset: identity_alauda
                  dataset_dir: /mnt/models/identity-alauda
                  template: default
                  cutoff_len: 128
                  max_samples: 16
                  overwrite_cache: true
                  preprocessing_num_workers: 2
                  output_dir: /workspace/output_models
                  logging_steps: 1
                  save_steps: 999999
                  overwrite_output_dir: true
                  per_device_train_batch_size: 2
                  gradient_accumulation_steps: 1
                  learning_rate: 2.0e-4
                  num_train_epochs: 1.0
                  bf16: false
                  fp16: false
                  report_to: none
                  EOL
                  llamafactory-cli train lf-sft.yaml
                  # Merge LoRA adapter into the base model — the doc's DO_MERGE step.
                  cat >lf-merge.yaml <<EOL
                  model_name_or_path: /mnt/models/qwen3-0.6b
                  adapter_name_or_path: /workspace/output_models
                  template: default
                  finetuning_type: lora
                  export_dir: /workspace/output_models_merged
                  export_size: 1
                  export_device: cpu
                  export_legacy_format: false
                  EOL
                  llamafactory-cli export lf-merge.yaml
                  ls -l /workspace/output_models_merged
YAML

cleanup() {
  gpu_kc -n "${NS}" delete vcjob "${JOB_NAME}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete pvc "${PVC_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C6: waiting for trainer pod..."
deadline=$((SECONDS + 600))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(gpu_kc -n "${NS}" get pod -l "volcano.sh/job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
[ -z "${POD}" ] && { log "C6: no pod"; exit 1; }
log "C6: pod=${POD}"

gpu_kc -n "${NS}" logs -f "${POD}" -c prepare --pod-running-timeout=1800s 2>&1 &
LP1=$!
deadline=$((SECONDS + 1800))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  init_ph="$(gpu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}' 2>/dev/null || true)"
  [ -n "${init_ph}" ] && break
  sleep 15
done
reap_logs "${LP1}"
log "C6: initContainer reason=${init_ph}"
if [ "${init_ph}" != "Completed" ]; then
  log "C6: init failed — dumping pod state"
  gpu_kc -n "${NS}" describe pod "${POD}" 2>&1 | tail -25 || true
  exit 1
fi

gpu_kc -n "${NS}" logs -f "${POD}" -c train 2>&1 &
LP2=$!
deadline=$((SECONDS + 1800))
ph=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  ph="$(gpu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${ph}" in Succeeded|Failed) break ;; esac
  sleep 15
done
reap_logs "${LP2}"
log "C6: pod phase=${ph}"
[ "${ph}" = "Succeeded" ]
