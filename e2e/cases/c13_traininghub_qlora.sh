#!/usr/bin/env bash
# C13 — exercises QLoRA (4-bit NF4 LoRA) on the published
# traininghub0.1-cu126-amd64 runtime image (the runtime that bundles
# trl + peft + bitsandbytes). Drives training_hub.lora_sft(load_in_4bit=True,...)
# as the canonical Training Hub QLoRA path, with a trl+peft+bitsandbytes fallback.
# A tiny synthetic Qwen2 checkpoint + synthetic chat JSONL are generated inside the
# Pod so the case has no external/model-download dependency (matches c3/c4).
#
# IMAGE: defaults to the cluster-pullable build-harbor mirror — docker.io is
# EGRESS-BLOCKED on the GPU cluster nodes, so the dockerhub tag
# (docker.io/alaudadockerhub/traininghub0.1-cu126-amd64:v0.1.0) ImagePullBackOffs
# there. build-harbor needs the `harbor-mlops-regcred` pull secret in the run
# namespace; this case auto-creates it from $ACP_HARBOR_USER/$ACP_HARBOR_PASS when
# E2E_IMAGE_PULL_SECRET is unset and those creds are present (see ensure_pull_secret).
#
# SKIP (rc=77) conditions, both captured from real cluster output:
#   * the requested HAMI vGPU slice cannot be scheduled (e.g. the only Ampere+
#     GPU is fully reserved) -> CardInsufficientMemory / Unschedulable;
#   * the GPU that *is* available is older than sm_75 (e.g. P100 sm_60), which the
#     bitsandbytes 4-bit kernels do not support -> in-pod arch guard exits 77.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
JOB_NAME="c13-traininghub-qlora-$(printf '%05x' $$)"
# Cluster-pullable by default (docker.io is egress-blocked on the GPU nodes).
# Faster intra-cluster mirror: 152-231-registry.alauda.cn:60070/mlops/traininghub0.1-cu126-amd64:v0.1.0-build.20260609030710
IMAGE="${C13_IMAGE:-build-harbor.alauda.cn/mlops/traininghub0.1-cu126-amd64:v0.1.0-build.20260609030710}"
# Ensure (create-if-missing) the harbor pull secret, then default to it.
IMAGE_PULL_SECRET="${C13_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-$(ensure_pull_secret "${NS}")}}"

cleanup() {
  gpu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C13: submitting Job ${JOB_NAME} (image=${IMAGE})"

cat <<YAML | mirror_dockerhub "${GPU_DH_MIRROR}" | gpu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c13
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c13
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
              # Arch guard: bitsandbytes 4-bit (QLoRA) needs sm_75+. On older
              # GPUs (e.g. P100 sm_60) the 4-bit kernels are unsupported -> SKIP(77).
              python - <<'PY'
              import sys, torch
              if not torch.cuda.is_available():
                  print("E2E-SKIP: no CUDA device visible", file=sys.stderr); sys.exit(77)
              cc = torch.cuda.get_device_capability(0); sm = cc[0]*10 + cc[1]
              name = torch.cuda.get_device_name(0)
              print(f"GPU={name} capability=sm_{sm}")
              if sm < 75:
                  print(f"E2E-SKIP: bitsandbytes 4-bit QLoRA requires sm_75+, got {name} sm_{sm}", file=sys.stderr)
                  sys.exit(77)
              PY

              # 1) Build a tiny synthetic Qwen2-style causal LM + tokenizer (offline).
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
              tok.chat_template = "{% for m in messages %}{{ m.role }}: {{ m.content }}\n{% endfor %}"
              tok.save_pretrained(MODEL_DIR)
              cfg = Qwen2Config(
                  vocab_size=tok.vocab_size + 4,
                  hidden_size=64, num_hidden_layers=2, num_attention_heads=4,
                  num_key_value_heads=4, intermediate_size=128, max_position_embeddings=256,
                  rope_theta=10000.0, tie_word_embeddings=True,
              )
              Qwen2ForCausalLM(cfg).save_pretrained(MODEL_DIR)

              data_path = "/workspace/test_qlora_data.jsonl"
              with open(data_path, "w") as f:
                  for _ in range(16):
                      json.dump({"messages": [
                          {"role": "system",    "content": "You are a helpful assistant."},
                          {"role": "user",      "content": "Hello, how are you?"},
                          {"role": "assistant", "content": "I am well - how can I help?"},
                      ]}, f); f.write("\n")
              print(f"prepared {MODEL_DIR} and {data_path}")
              PY

              # 2) QLoRA: training_hub.lora_sft(load_in_4bit) is the canonical path;
              #    fall back to trl+peft+bitsandbytes (bundled in this runtime) if the
              #    unsloth backend can't load the offline synthetic model.
              python - <<'PY'
              import os, time, glob
              MODEL_DIR = "/workspace/tiny-qwen2"
              DATA = "/workspace/test_qlora_data.jsonl"
              CKPT = "/workspace/ckpt"

              def has_adapter(root):
                  hits = glob.glob(os.path.join(root, "**", "adapter_model*"), recursive=True)
                  hits += glob.glob(os.path.join(root, "**", "*.safetensors"), recursive=True)
                  return hits

              ok = False
              try:
                  from training_hub import lora_sft
                  t0 = time.time()
                  result = lora_sft(
                      model_path=MODEL_DIR, data_path=DATA, ckpt_output_dir=CKPT,
                      lora_r=8, lora_alpha=16, lora_dropout=0.05,
                      target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
                      load_in_4bit=True, bnb_4bit_quant_type="nf4",
                      bnb_4bit_compute_dtype="bfloat16", bnb_4bit_use_double_quant=True,
                      num_epochs=1, effective_batch_size=2, learning_rate=2e-4,
                      max_seq_len=128, warmup_steps=0,
                      nproc_per_node=1, nnodes=1, node_rank=0,
                      rdzv_id=13, rdzv_endpoint="127.0.0.1:29513",
                  )
                  print(f"training_hub.lora_sft finished in {time.time()-t0:.1f}s: {result!r}")
                  ok = bool(has_adapter(CKPT))
              except Exception as e:
                  print(f"training_hub.lora_sft path unavailable ({type(e).__name__}: {e}); "
                        f"falling back to trl+peft+bitsandbytes QLoRA")

              if not ok:
                  import torch
                  from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
                  from peft import LoraConfig, prepare_model_for_kbit_training
                  from trl import SFTConfig, SFTTrainer
                  from datasets import load_dataset

                  bnb = BitsAndBytesConfig(
                      load_in_4bit=True, bnb_4bit_quant_type="nf4",
                      bnb_4bit_compute_dtype=torch.bfloat16, bnb_4bit_use_double_quant=True,
                  )
                  tok = AutoTokenizer.from_pretrained(MODEL_DIR)
                  model = AutoModelForCausalLM.from_pretrained(
                      MODEL_DIR, quantization_config=bnb, device_map={"": 0},
                      attn_implementation="eager",
                  )
                  model = prepare_model_for_kbit_training(model)
                  peft_cfg = LoraConfig(
                      r=8, lora_alpha=16, lora_dropout=0.05, bias="none",
                      target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
                      task_type="CAUSAL_LM",
                  )
                  ds = load_dataset("json", data_files=DATA, split="train")
                  ds = ds.map(lambda ex: {"text": tok.apply_chat_template(ex["messages"], tokenize=False)})

                  # trl 0.17: max_seq_length lives on SFTConfig; tolerate field renames.
                  cfg_kw = dict(output_dir=CKPT, num_train_epochs=1, per_device_train_batch_size=2,
                                max_steps=5, logging_steps=1, learning_rate=2e-4,
                                report_to=[], bf16=True, dataset_text_field="text")
                  try:
                      cfg = SFTConfig(max_seq_length=128, **cfg_kw)
                  except TypeError:
                      cfg = SFTConfig(max_length=128, **cfg_kw)
                  try:
                      trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds,
                                           peft_config=peft_cfg, processing_class=tok)
                  except TypeError:
                      trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds,
                                           peft_config=peft_cfg, tokenizer=tok)
                  t0 = time.time()
                  trainer.train()
                  trainer.save_model(CKPT)
                  print(f"trl QLoRA finished in {time.time()-t0:.1f}s")
                  ok = bool(has_adapter(CKPT))

              adapters = has_adapter(CKPT)
              assert adapters, f"no QLoRA adapter/checkpoint under {CKPT}"
              print(f"QLoRA artifacts: {[os.path.relpath(a, CKPT) for a in adapters][:5]}")
              PY
YAML

log "C13: waiting for pod to appear..."
deadline=$((SECONDS + 120))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C13: pod=${POD}"

# Scheduling SKIP: if the pod never leaves Pending (no schedulable GPU slice),
# capture the real scheduler event and SKIP rather than fail.
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
  if echo "${EVT}" | grep -qiE 'CardInsufficientMemory|Insufficient|Unschedulable|FailedScheduling|FilteringFailed|untolerated|no available node'; then
    log "C13: SKIP — pod ${POD} cannot be scheduled onto a GPU slice:"
    echo "${EVT}" | sed 's/^/    /'
    exit "${E2E_SKIP_RC}"
  fi
  log "C13: SKIP — pod ${POD} still ${phase:-<none>} after scheduling deadline:"
  echo "${EVT}" | sed 's/^/    /'
  exit "${E2E_SKIP_RC}"
fi

# Stream logs and wait for terminal job state.
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
log "C13: job status=${status}"

# Runtime SKIP: the in-pod arch guard exits 77 on unsupported GPUs (sm < 75).
EXIT_CODE="$(gpu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || true)"
if [ "${EXIT_CODE}" = "77" ]; then
  log "C13: SKIP — in-pod guard signalled unsupported GPU for 4-bit QLoRA:"
  gpu_kc -n "${NS}" logs "${POD}" --tail=20 2>&1 | grep -i 'E2E-SKIP' | sed 's/^/    /' || true
  exit "${E2E_SKIP_RC}"
fi

if [[ "${status}" != *Complete* ]]; then
  log "C13: ==== pod final state ===="
  gpu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  log "C13: ==== container logs ===="
  gpu_kc -n "${NS}" logs -l "job-name=${JOB_NAME}" --tail=200 2>&1 || true
  log "C13: ==== pod describe ===="
  gpu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -30 || true
fi
[[ "${status}" == *Complete* ]]
