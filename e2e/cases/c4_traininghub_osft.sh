#!/usr/bin/env bash
# C4 — exercises training_hub.osft against traininghub0.1-cu126-amd64:v0.1.0
# (osft-comprehensive-tutorial.ipynb path). Synthetic tiny Qwen2 model + JSONL,
# nproc_per_node=1.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${GPU_NAMESPACE}"
JOB_NAME="c4-traininghub-osft-$(printf '%05x' $$)"
IMAGE="${C4_IMAGE:-build-harbor.alauda.cn/mlops/traininghub0.1-cu126-amd64:v0.1.0-build.20260609030710}"

cleanup() {
  gpu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C4: submitting Job ${JOB_NAME} (image=${IMAGE})"

cat <<YAML | gpu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c4
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c4
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      imagePullSecrets:
        - name: harbor-mlops-regcred
      volumes:
        - name: workspace
          emptyDir: {}
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 2Gi
      containers:
        - name: trainer
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - { name: HF_HOME, value: /workspace/hf_cache }
            - { name: HF_HUB_OFFLINE, value: "1" }
            - { name: TRANSFORMERS_OFFLINE, value: "1" }
            - { name: TORCH_HOME, value: /workspace/torch_cache }
            - { name: TRITON_CACHE_DIR, value: /workspace/triton_cache }
            - { name: PYTHONUNBUFFERED, value: "1" }
          volumeMounts:
            - { name: workspace, mountPath: /workspace }
            - { name: dshm, mountPath: /dev/shm }
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
          command: [bash, -ec]
          args:
            - |
              set -ex
              cd /workspace
              # training_hub is bundled in the runtime image.
              python - <<'PY'
              import os, json, torch
              from transformers import GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM
              from tokenizers import ByteLevelBPETokenizer

              MODEL_DIR = "/workspace/tiny-qwen2"
              os.makedirs(MODEL_DIR, exist_ok=True)
              torch.manual_seed(0)
              bpe = ByteLevelBPETokenizer()
              bpe.train_from_iterator(
                  ["hello world", "the quick brown fox", "alauda ai e2e"], vocab_size=512,
                  min_frequency=1, special_tokens=["<pad>", "<s>", "</s>", "<unk>"],
              )
              bpe.save_model(MODEL_DIR)
              tok = GPT2TokenizerFast(
                  vocab_file=f"{MODEL_DIR}/vocab.json",
                  merges_file=f"{MODEL_DIR}/merges.txt",
                  unk_token="<unk>", bos_token="<s>", eos_token="</s>", pad_token="<pad>",
              )
              tok.chat_template = (
                  "{% for m in messages %}{{ m.role }}: {{ m.content }}\n{% endfor %}"
              )
              tok.save_pretrained(MODEL_DIR)

              cfg = Qwen2Config(
                  vocab_size=tok.vocab_size + 4,
                  hidden_size=64, num_hidden_layers=2, num_attention_heads=4,
                  num_key_value_heads=4, intermediate_size=128, max_position_embeddings=256,
                  rope_theta=10000.0, tie_word_embeddings=True,
              )
              Qwen2ForCausalLM(cfg).save_pretrained(MODEL_DIR)

              data_path = "/workspace/test_osft_data.jsonl"
              with open(data_path, "w") as f:
                  for _ in range(16):
                      json.dump({"messages": [
                          {"role": "system",    "content": "You are a domain expert."},
                          {"role": "user",      "content": "Summarize Alauda AI."},
                          {"role": "assistant", "content": "Alauda AI provides MLOps on Kubernetes."},
                      ]}, f); f.write("\n")
              print(f"prepared {MODEL_DIR} and {data_path}")
              PY

              python - <<'PY'
              import os, time
              from training_hub import osft
              t0 = time.time()
              result = osft(
                  model_path="/workspace/tiny-qwen2",
                  data_path="/workspace/test_osft_data.jsonl",
                  ckpt_output_dir="/workspace/ckpt",
                  unfreeze_rank_ratio=0.25,
                  num_epochs=1,
                  effective_batch_size=2,
                  learning_rate=5e-6,
                  max_seq_len=128,
                  max_tokens_per_gpu=256,
                  data_output_dir="/workspace/data_cache",
                  warmup_steps=0,
                  checkpoint_at_epoch=True,
                  accelerate_full_state_at_epoch=False,
                  nproc_per_node=1,
                  nnodes=1,
                  node_rank=0,
                  rdzv_id=2,
                  rdzv_endpoint="127.0.0.1:29501",
                  use_liger=False,
              )
              print(f"osft finished in {time.time()-t0:.1f}s, result={result!r}")
              hf_dir = "/workspace/ckpt/hf_format"
              assert os.path.isdir(hf_dir), f"no hf_format dir at {hf_dir}"
              ckpts = sorted(os.listdir(hf_dir))
              assert ckpts, f"no checkpoints under {hf_dir}"
              print(f"checkpoints: {ckpts}")
              PY
YAML

log "C4: waiting for pod to appear..."
deadline=$((SECONDS + 300))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C4: pod=${POD}"

if [ -n "${POD}" ]; then
  gpu_kc -n "${NS}" logs -f "${POD}" 2>&1 &
  LOGS_PID=$!
fi

deadline=$((SECONDS + 2400))
status=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  status="$(gpu_kc -n "${NS}" get job "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null || true)"
  case "${status}" in *Complete*) break ;; *Failed*) break ;; esac
  sleep 15
done
[ -n "${LOGS_PID:-}" ] && wait "${LOGS_PID}" 2>/dev/null || true
log "C4: job status=${status}"
if [[ "${status}" != *Complete* ]]; then
  log "C4: ==== pod final state ===="
  gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  gpu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -40 || true
fi
[[ "${status}" == *Complete* ]]
