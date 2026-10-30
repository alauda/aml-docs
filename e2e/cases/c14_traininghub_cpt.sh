#!/usr/bin/env bash
# C14 — exercises continued pre-training (CPT) on the published
# traininghub0.1-cu126-amd64 runtime image. Drives
# training_hub.sft(is_pretraining=True, block_size=..., document_column_name="text")
# over a tiny synthetic RAW-TEXT corpus + tiny synthetic Qwen2 checkpoint, both
# generated inside the Pod (no external/model/corpus download — matches c3/c4).
# CPT is full-parameter and uses torch SDPA, so (unlike c13 QLoRA) it has no
# sm_75 requirement; flash_attn is force-disabled for older-GPU compatibility.
#
# IMAGE: defaults to the cluster-pullable build-harbor mirror — docker.io is
# EGRESS-BLOCKED on the GPU cluster nodes (the dockerhub tag ImagePullBackOffs).
# build-harbor needs the `harbor-mlops-regcred` pull secret in the run namespace;
# this case auto-creates it from $ACP_HARBOR_USER/$ACP_HARBOR_PASS when
# E2E_IMAGE_PULL_SECRET is unset and those creds are present (see ensure_pull_secret).
#
# SKIP (rc=77): the requested HAMI vGPU slice cannot be scheduled (the captured
# scheduler event, e.g. CardInsufficientMemory / Unschedulable, is printed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
JOB_NAME="c14-traininghub-cpt-$(printf '%05x' $$)"
# Cluster-pullable by default (docker.io is egress-blocked on the GPU nodes).
# Faster intra-cluster mirror: 152-231-registry.alauda.cn:60070/mlops/traininghub0.1-cu126-amd64:v0.1.0-build.20260609030710
IMAGE="${C14_IMAGE:-build-harbor.alauda.cn/mlops/traininghub0.1-cu126-amd64:v0.1.0-build.20260609030710}"
# Ensure (create-if-missing) the harbor pull secret, then default to it.
IMAGE_PULL_SECRET="${C14_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-$(ensure_pull_secret "${NS}")}}"

cleanup() {
  gpu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C14: submitting Job ${JOB_NAME} (image=${IMAGE})"

cat <<YAML | mirror_dockerhub "${GPU_DH_MIRROR}" | gpu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c14
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c14
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
          terminationMessagePolicy: FallbackToLogsOnError
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
              # 1) Tiny synthetic Qwen2-style base model + tokenizer (offline).
              python - <<'PY'
              import os, json, torch
              from transformers import GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM
              from tokenizers import ByteLevelBPETokenizer

              MODEL_DIR = "/workspace/tiny-qwen2"
              os.makedirs(MODEL_DIR, exist_ok=True)
              torch.manual_seed(0)
              bpe = ByteLevelBPETokenizer()
              bpe.train_from_iterator(
                  ["hello world", "the quick brown fox", "alauda ai continued pretraining"],
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

              # 2) Synthetic RAW-TEXT corpus: one document per line under "text".
              data_path = "/workspace/test_cpt_data.jsonl"
              docs = [
                  "Alauda AI is an MLOps platform that runs fine-tuning and inference on Kubernetes.",
                  "Continued pre-training adapts a base language model to a new domain using unlabeled text.",
                  "The training hub library wraps SFT, OSFT, LoRA, QLoRA and continued pre-training.",
                  "Kubeflow Trainer v2 submits distributed TrainJobs onto GPU or NPU nodes.",
              ] * 8
              with open(data_path, "w") as f:
                  for d in docs:
                      json.dump({"text": d}, f); f.write("\n")
              print(f"prepared base model {MODEL_DIR} and raw-text corpus {data_path}")
              PY

              # 3) Continued pre-training via training_hub.sft(is_pretraining=True).
              python - <<'PY'
              import os, time
              from training_hub import sft
              t0 = time.time()
              result = sft(
                  model_path="/workspace/tiny-qwen2",
                  data_path="/workspace/test_cpt_data.jsonl",
                  ckpt_output_dir="/workspace/ckpt",
                  # --- continued pre-training (CPT) ---
                  is_pretraining=True,
                  block_size=128,
                  document_column_name="text",
                  # --- core training ---
                  num_epochs=1,
                  effective_batch_size=2,
                  learning_rate=5e-6,
                  max_seq_len=128,
                  max_tokens_per_gpu=256,
                  data_output_dir="/workspace/data_cache",
                  warmup_steps=0,
                  checkpoint_at_epoch=True,
                  accelerate_full_state_at_epoch=False,
                  nproc_per_node=1, nnodes=1, node_rank=0,
                  rdzv_id=14, rdzv_endpoint="127.0.0.1:29514",
                  disable_flash_attn=True,
                  use_liger=False,
              )
              print(f"CPT (sft is_pretraining) finished in {time.time()-t0:.1f}s: {result!r}")
              hf_dir = "/workspace/ckpt/hf_format"
              assert os.path.isdir(hf_dir), f"no hf_format dir at {hf_dir}"
              ckpts = sorted(os.listdir(hf_dir))
              assert ckpts, f"no checkpoints under {hf_dir}"
              print(f"checkpoints: {ckpts}")
              PY
YAML

log "C14: waiting for pod to appear..."
deadline=$((SECONDS + 120))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C14: pod=${POD}"

# Scheduling SKIP: if no schedulable GPU slice, capture the scheduler event and SKIP.
sched_deadline=$((SECONDS + 300))
phase=""
while [ "${SECONDS}" -lt "${sched_deadline}" ]; do
  phase="$(gpu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in Running|Succeeded|Failed) break ;; esac
  sleep 5
done
if [ "${phase}" = "Pending" ] || [ -z "${phase}" ]; then
  EVT="$(gpu_kc -n "${NS}" get event --field-selector "involvedObject.name=${POD}" \
         -o jsonpath='{range .items[*]}{.reason}: {.message}{"\n"}{end}' 2>/dev/null | tail -3)"
  log "C14: SKIP — pod ${POD} still ${phase:-<none>} (no schedulable GPU slice):"
  echo "${EVT}" | sed 's/^/    /'
  exit "${E2E_SKIP_RC}"
fi

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
log "C14: job status=${status}"
if [[ "${status}" != *Complete* ]]; then
  log "C14: ==== pod final state ===="
  gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  log "C14: ==== container logs ===="
  gpu_kc -n "${NS}" logs -l "job-name=${JOB_NAME}" --tail=200 2>&1 || true
  log "C14: ==== pod describe ===="
  gpu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -30 || true
fi
[[ "${status}" == *Complete* ]]
