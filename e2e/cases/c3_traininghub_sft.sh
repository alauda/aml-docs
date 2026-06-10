#!/usr/bin/env bash
# C3 — exercises training_hub.sft against the published
# traininghub0.1-cu126-amd64:v0.1.0 runtime image (used by sft-comprehensive-tutorial.ipynb).
# Tiny synthetic Qwen2-style HF checkpoint + synthetic JSONL are generated inside the
# Pod so the case has no external dependency. nproc_per_node is forced to 1
# to keep the smoke case small.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
JOB_NAME="c3-traininghub-sft-$(printf '%05x' $$)"
IMAGE="${C3_IMAGE:-docker.io/alaudadockerhub/traininghub0.1-cu126-amd64:v0.1.0}"
IMAGE_PULL_SECRET="${C3_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"

cleanup() {
  gpu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C3: submitting Job ${JOB_NAME} (image=${IMAGE})"

# Drive sft() from inside the pod. The notebook caps nproc_per_node at 1 for the
# single_gpu_dev preset; we do the same here. Liger is disabled because the
# image's CUDA *runtime* lacks nvcc (see training-runtimes.mdx — same caveat
# applies to JIT op compilation).
cat <<YAML | mirror_dockerhub "${GPU_DH_MIRROR}" | gpu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c3
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c3
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
$(yaml_image_pull_secrets 6 "${IMAGE_PULL_SECRET}")
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
              # training_hub is bundled in the runtime image; nothing to install.
              python - <<'PY'
              # 1) Build a tiny synthetic Qwen2-style causal LM checkpoint + tokenizer
              #    so we don't need to pull a real model from HF.
              import os, json, torch
              from transformers import AutoTokenizer, Qwen2Config, Qwen2ForCausalLM

              MODEL_DIR = "/workspace/tiny-qwen2"
              os.makedirs(MODEL_DIR, exist_ok=True)
              torch.manual_seed(0)
              # Reuse a small public tokenizer's vocab via local cache fallback: build
              # a 256-token byte-level GPT2 tokenizer instead, fully offline.
              from transformers import GPT2TokenizerFast
              from tokenizers import ByteLevelBPETokenizer
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
              tok.save_pretrained(MODEL_DIR)

              cfg = Qwen2Config(
                  vocab_size=tok.vocab_size + 4,
                  hidden_size=64, num_hidden_layers=2, num_attention_heads=4,
                  num_key_value_heads=4, intermediate_size=128, max_position_embeddings=256,
                  rope_theta=10000.0, tie_word_embeddings=True,
              )
              model = Qwen2ForCausalLM(cfg)
              model.save_pretrained(MODEL_DIR)
              # add the chat template the training_hub data path expects.
              tok.chat_template = (
                  "{% for m in messages %}{{ m.role }}: {{ m.content }}\n{% endfor %}"
              )
              tok.save_pretrained(MODEL_DIR)
              print(f"tiny model at {MODEL_DIR}: cfg={cfg.to_dict()}")

              # 2) Synthetic JSONL — identical schema to sft-comprehensive-tutorial.ipynb's
              #    dummy dataset (10 short chat turns).
              data_path = "/workspace/test_sft_data.jsonl"
              with open(data_path, "w") as f:
                  for _ in range(16):
                      json.dump({"messages": [
                          {"role": "system",    "content": "You are a helpful assistant."},
                          {"role": "user",      "content": "Hello, how are you?"},
                          {"role": "assistant", "content": "I am well — how can I help?"},
                      ]}, f); f.write("\n")
              print(f"wrote {data_path}")
              PY

              python - <<'PY'
              # 3) Now call training_hub.sft with single_gpu_dev distributed config.
              import os, time
              from training_hub import sft
              os.environ.setdefault("HF_HUB_OFFLINE", "1")
              os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
              t0 = time.time()
              result = sft(
                  model_path="/workspace/tiny-qwen2",
                  data_path="/workspace/test_sft_data.jsonl",
                  ckpt_output_dir="/workspace/ckpt",
                  num_epochs=1,
                  effective_batch_size=2,
                  learning_rate=1e-5,
                  max_seq_len=128,
                  max_tokens_per_gpu=256,
                  data_output_dir="/workspace/data_cache",
                  warmup_steps=0,
                  checkpoint_at_epoch=True,
                  accelerate_full_state_at_epoch=False,
                  nproc_per_node=1,
                  nnodes=1,
                  node_rank=0,
                  rdzv_id=1,
                  rdzv_endpoint="127.0.0.1:29500",
                  disable_flash_attn=True,
                  use_liger=False,
              )
              print(f"sft finished in {time.time()-t0:.1f}s, result={result!r}")
              # Verify at least one checkpoint landed.
              hf_dir = "/workspace/ckpt/hf_format"
              assert os.path.isdir(hf_dir), f"no hf_format dir at {hf_dir}"
              ckpts = sorted(os.listdir(hf_dir))
              assert ckpts, f"no checkpoints under {hf_dir}"
              print(f"checkpoints: {ckpts}")
              PY
YAML

log "C3: waiting for pod to appear..."
deadline=$((SECONDS + 300))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C3: pod=${POD}"

# Stream logs in the background; tolerate pod termination mid-stream.
if [ -n "${POD}" ]; then
  gpu_kc -n "${NS}" logs -f "${POD}" 2>&1 &
  LOGS_PID=$!
fi

# Wait for terminal job state.
deadline=$((SECONDS + 2400))
status=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  status="$(gpu_kc -n "${NS}" get job "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null || true)"
  case "${status}" in *Complete*) break ;; *Failed*) break ;; esac
  sleep 15
done
[ -n "${LOGS_PID:-}" ] && wait "${LOGS_PID}" 2>/dev/null || true
log "C3: job status=${status}"
# On failure, dump a final tail of the previous container's logs and pod state.
if [[ "${status}" != *Complete* ]]; then
  log "C3: ==== pod final state ===="
  gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  log "C3: ==== container logs ===="
  gpu_kc -n "${NS}" logs -l "job-name=${JOB_NAME}" --tail=200 2>&1 || true
  log "C3: ==== pod describe ===="
  gpu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -30 || true
fi
[[ "${status}" == *Complete* ]]
