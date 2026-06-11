#!/usr/bin/env bash
# C5 — exercises fine-tune-with-trainer-v2.ipynb (LlamaFactory SFT via Trainer v2).
# The published TrainingRuntime in the notebook has three replicatedJobs:
#   dataset-initializer  → clones a private GitLab dataset
#   model-initializer    → clones a private GitLab base model
#   trainer              → runs llamafactory-cli train
# Both initializers need MODEL_REPO_GIT_USER/TOKEN secrets. To verify the
# procedure with synthetic data, this case replaces the two initializers with
# a single Python-only step that materialises a tiny Qwen2 HF model + identity
# JSONL into the shared workspace; the trainer step is unchanged from the doc.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
# Per-run suffix so re-runs / concurrent runs don't share PVC contents or fight
# over the same TrainingRuntime. The trap below tears down both.
RUN_ID="$(printf '%05x' $$)-$(date -u +%s)"
RUNTIME="c5-llamafactory-finetune-runtime-${RUN_ID}"
PVC_NAME="c5-models-${RUN_ID}"
IMAGE="${LF_IMAGE:-docker.io/alaudadockerhub/llamafactory0.9-cu126-amd64:v0.1.0}"
IMAGE_PULL_SECRET="${LF_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
RWX_STORAGE_CLASS="${C5_RWX_STORAGE_CLASS:-${E2E_RWX_STORAGE_CLASS:-}}"
NODE_SELECTOR_KEY="${C5_NODE_SELECTOR_KEY:-${E2E_GPU_NODE_SELECTOR_KEY:-}}"
NODE_SELECTOR_VALUE="${C5_NODE_SELECTOR_VALUE:-${E2E_GPU_NODE_SELECTOR_VALUE:-}}"

log "C5: ensuring shared RWX PVC ${PVC_NAME} exists"
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

log "C5: applying TrainingRuntime ${RUNTIME} to ns/${NS} (image=${IMAGE})"
cat <<YAML | mirror_dockerhub "${GPU_DH_MIRROR}" | retry_apply gpu_kc
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainingRuntime
metadata:
  name: ${RUNTIME}
  namespace: ${NS}
  labels:
    trainer.kubeflow.org/framework: torch
spec:
  mlPolicy:
    numNodes: 1
    torch:
      numProcPerNode: auto
  template:
    spec:
      replicatedJobs:
        - name: dataset-initializer
          template:
            metadata:
              labels:
                trainer.kubeflow.org/trainjob-ancestor-step: dataset-initializer
            spec:
              template:
                spec:
                  securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
$(yaml_node_selector 18 "${NODE_SELECTOR_KEY}" "${NODE_SELECTOR_VALUE}")
$(yaml_image_pull_secrets 18 "${IMAGE_PULL_SECRET}")
                  volumes:
                    - name: models
                      persistentVolumeClaim: { claimName: ${PVC_NAME} }
                  containers:
                    - name: dataset-initializer
                      volumeMounts:
                        - { name: models, mountPath: /mnt/models }
                      image: ${IMAGE}
                      command: [bash, -ec]
                      args:
                        - |
                          set -ex
                          mkdir -p /mnt/models/identity-alauda
                          python - <<'PY'
                          import json, os
                          out = "/mnt/models/identity-alauda"
                          os.makedirs(out, exist_ok=True)
                          # LlamaFactory data_info format
                          with open(f"{out}/dataset_info.json", "w") as f:
                              json.dump({
                                  "identity_alauda": {
                                      "file_name": "identity.json",
                                      "formatting": "alpaca",
                                      "columns": {"prompt": "instruction", "query": "input", "response": "output"},
                                  }
                              }, f)
                          rows = [
                              {"instruction": "Who are you?",     "input": "", "output": "I am Alauda AI, a helpful assistant."},
                              {"instruction": "What can you do?", "input": "", "output": "I can answer questions, summarize text, and write code."},
                              {"instruction": "Who made you?",    "input": "", "output": "I was fine-tuned on the Alauda AI platform."},
                          ] * 8
                          with open(f"{out}/identity.json", "w") as f:
                              json.dump(rows, f)
                          PY
                          ls -l /mnt/models/identity-alauda
                      resources:
                        requests: { cpu: 100m, memory: 128Mi }
                        limits:   { cpu: 500m, memory: 1Gi }
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities: { drop: [ALL] }
                        runAsNonRoot: true
                        seccompProfile: { type: RuntimeDefault }
        - name: model-initializer
          dependsOn:
            - name: dataset-initializer
              status: Complete
          template:
            metadata:
              labels:
                trainer.kubeflow.org/trainjob-ancestor-step: model-initializer
            spec:
              template:
                spec:
                  securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
$(yaml_node_selector 18 "${NODE_SELECTOR_KEY}" "${NODE_SELECTOR_VALUE}")
$(yaml_image_pull_secrets 18 "${IMAGE_PULL_SECRET}")
                  volumes:
                    - name: models
                      persistentVolumeClaim: { claimName: ${PVC_NAME} }
                  containers:
                    - name: model-initializer
                      volumeMounts:
                        - { name: models, mountPath: /mnt/models }
                      image: ${IMAGE}
                      command: [bash, -ec]
                      args:
                        - |
                          set -ex
                          # Synthesise a tiny Qwen2 model that LlamaFactory can SFT in <1 min.
                          python - <<'PY'
                          import os, torch
                          from transformers import GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM
                          from tokenizers import ByteLevelBPETokenizer
                          MODEL_DIR = "/mnt/models/qwen3-0.6b"  # keep notebook's name
                          os.makedirs(MODEL_DIR, exist_ok=True)
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
                          print("model_dir", MODEL_DIR, "vocab", tok.vocab_size)
                          PY
                          ls -l /mnt/models/qwen3-0.6b
                      resources:
                        requests: { cpu: 100m, memory: 128Mi }
                        limits:   { cpu: 1, memory: 4Gi }
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities: { drop: [ALL] }
                        runAsNonRoot: true
                        seccompProfile: { type: RuntimeDefault }
        - name: trainer
          dependsOn:
            - name: model-initializer
              status: Complete
          template:
            metadata:
              labels:
                trainer.kubeflow.org/trainjob-ancestor-step: trainer
            spec:
              backoffLimit: 0
              template:
                spec:
                  securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
$(yaml_node_selector 18 "${NODE_SELECTOR_KEY}" "${NODE_SELECTOR_VALUE}")
$(yaml_image_pull_secrets 18 "${IMAGE_PULL_SECRET}")
                  volumes:
                    - { name: workspace, emptyDir: {} }
                    - name: models
                      persistentVolumeClaim: { claimName: ${PVC_NAME} }
                    - name: dshm
                      emptyDir: { medium: Memory, sizeLimit: 1Gi }
                  containers:
                    - name: node
                      image: ${IMAGE}
                      env:
                        - { name: HF_HOME, value: /workspace/hf_cache }
                        - { name: TORCH_HOME, value: /workspace/torch_cache }
                        - { name: TRITON_CACHE_DIR, value: /workspace/triton_cache }
                        - { name: PYTHONUNBUFFERED, value: "1" }
                      volumeMounts:
                        - { mountPath: /workspace, name: workspace }
                        - { mountPath: /mnt/models, name: models }
                        - { mountPath: /dev/shm, name: dshm }
                      command: [bash, -ec]
                      args:
                        - |
                          set -ex
                          # Catalog runtime ships CUDA *runtime* but not the toolkit;
                          # transformers→accelerate eagerly imports deepspeed which fails
                          # without nvcc. We don't need deepspeed for a LoRA smoke run.
                          # Stub the deepspeed module via PYTHONPATH so import succeeds.
                          mkdir -p /workspace/stubs/deepspeed
                          cat >/workspace/stubs/deepspeed/__init__.py <<'PY'
                          class DeepSpeedEngine: ...
                          PY
                          export PYTHONPATH=/workspace/stubs:${PYTHONPATH:-}
                          # Also keep matplotlib/fontconfig writable.
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
                          lora_dropout: 0.0
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
                          plot_loss: false
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
                          ls -l /workspace/output_models
                      resources:
                        requests: { cpu: "1", memory: 4Gi }
                        limits:
                          cpu: "4"
                          memory: 12Gi
                          nvidia.com/gpualloc: 1
                          nvidia.com/gpucores: 50
                          nvidia.com/gpumem: "8192"
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities: { drop: [ALL] }
                        runAsNonRoot: true
                        seccompProfile: { type: RuntimeDefault }
YAML

log "C5: submitting TrainJob against ${RUNTIME}"
TJ_NAME=$(cat <<YAML | retry_create gpu_kc -o jsonpath='{.metadata.name}'
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  generateName: c5-llamafactory-
  namespace: ${NS}
spec:
  runtimeRef:
    apiGroup: trainer.kubeflow.org
    kind: TrainingRuntime
    name: ${RUNTIME}
  suspend: false
  trainer:
    numNodes: 1
YAML
)
log "C5: trainjob=${TJ_NAME}"

cleanup() {
  gpu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete trainingruntime "${RUNTIME}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete pvc "${PVC_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

# Walk every replicatedJob in turn — initializer pods exit quickly, trainer runs longer.
for RJOB in dataset-initializer model-initializer trainer; do
  log "C5: waiting for ${RJOB} pod..."
  deadline=$((SECONDS + 600))
  POD=""
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    POD="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}" "${RJOB}")"
    [ -n "${POD}" ] && break
    sleep 5
  done
  if [ -z "${POD}" ]; then log "C5: ${RJOB} pod did not appear"; exit 1; fi
  log "C5: ${RJOB} pod=${POD}"
  gpu_kc -n "${NS}" logs -f "${POD}" 2>&1 &
  LPID=$!
  deadline=$((SECONDS + 2400))
  ph=""
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    ph="$(gpu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "${ph}" in Succeeded|Failed) break ;; esac
    sleep 15
  done
  # Reap the log follower — `wait` alone would block if the pod never reached
  # a terminal phase and `logs -f` is still streaming.
  reap_logs "${LPID}"
  log "C5: ${RJOB} pod phase=${ph}"
  [ "${ph}" = "Succeeded" ] || exit 1
done

log "C5: all steps Succeeded"
