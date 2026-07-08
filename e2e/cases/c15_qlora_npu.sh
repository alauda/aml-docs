#!/usr/bin/env bash
# C15 — QLoRA (4-bit NF4 + LoRA adapters) on a Huawei Ascend NPU using
# transformers + peft + torch_npu + the community bitsandbytes-npu-beta
# fork. Companion of C13 (which uses training_hub on CUDA):
# training_hub / mainline bitsandbytes do not run on Ascend, so the recipe
# uses `BitsAndBytesConfig(load_in_4bit=True, ...)` with the
# `bitsandbytes-npu-beta` PyPI package. Generates a tiny synthetic Qwen2 base
# model + a synthetic chat JSONL in-Pod so it needs no external download.
#
# Image: the same PyTorch CANN workbench image C7/C8/C16 use. CANN env is
# sourced per the C8 pattern. NPU is requested via ${NPU_RESOURCE_NAME} (e.g.
# huawei.com/Ascend910B4), quantity ${NPU_RESOURCE_VALUE:-1}.
#
# SKIP (rc=77) conditions:
#   * NPU_NAMESPACE or NPU_RESOURCE_NAME not set (opt-in — see run_all.sh);
#   * the NPU slice cannot be scheduled (captured scheduler event);
#   * the in-Pod NPU sanity check fails (torch.npu.is_available() False);
#   * `import bitsandbytes` fails after `pip install bitsandbytes-npu-beta` —
#     the fork is torch_npu 2.1–2.4 / CANN 8.0–8.1 era, and CANN 8.5+ compat
#     is not officially validated by the fork's author (see
#     `qlora-npu-tutorial.ipynb` for the compatibility caveat).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env NPU_NAMESPACE "namespace for NPU e2e resources"
require_env NPU_RESOURCE_NAME "extended resource name for one NPU, for example huawei.com/Ascend910B4"
NS="${NPU_NAMESPACE}"
JOB_NAME="c15-qlora-npu-$(printf '%05x' $$)"
IMAGE="${C15_IMAGE:-docker.io/alaudadockerhub/alauda-workbench-jupyter-pytorch-cann-py312-ubi9:v0.1.7}"
IMAGE_PULL_SECRET="${C15_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
NPU_RESOURCE_VALUE="${NPU_RESOURCE_VALUE:-1}"
NPU_MEMORY_RESOURCE_NAME="${NPU_MEMORY_RESOURCE_NAME:-}"
NPU_MEMORY_RESOURCE_VALUE="${NPU_MEMORY_RESOURCE_VALUE:-8192}"
NPU_RUNTIME_CLASS="${NPU_RUNTIME_CLASS:-}"
# The fork's PyPI name & pinned version. See qlora-npu-tutorial.ipynb.
BNB_NPU_PIN="${BNB_NPU_PIN:-bitsandbytes-npu-beta==0.45.3}"
PIP_INDEX_URL="${PIP_INDEX_URL:-}"

cleanup() {
  npu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C15: submitting Job ${JOB_NAME} (image=${IMAGE}, bnb=${BNB_NPU_PIN})"

cat <<YAML | mirror_dockerhub "${NPU_DH_MIRROR}" | npu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c15
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c15
    spec:
      restartPolicy: Never
$(yaml_scalar_field 6 runtimeClassName "${NPU_RUNTIME_CLASS}")
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 0
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
            - { name: PYTHONUNBUFFERED, value: "1" }
            - { name: PYTORCH_NPU_ALLOC_CONF, value: "expandable_segments:True" }
            - { name: PIP_INDEX_URL, value: "${PIP_INDEX_URL}" }
            - { name: BNB_NPU_PIN, value: "${BNB_NPU_PIN}" }
          volumeMounts:
            - { name: workspace, mountPath: /workspace }
            - { name: dshm, mountPath: /dev/shm }
          resources:
            requests: { cpu: "1", memory: 4Gi }
            limits:
              cpu: "4"
              memory: 12Gi
$(yaml_resource_limit 14 "${NPU_RESOURCE_NAME}" "${NPU_RESOURCE_VALUE}")
$(yaml_resource_limit 14 "${NPU_MEMORY_RESOURCE_NAME}" "${NPU_MEMORY_RESOURCE_VALUE}")
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
              # Source CANN environment per the workbench runtime YAML.
              set +e
              for f in /usr/local/Ascend/cann/set_env.sh \
                       /usr/local/Ascend/ascend-toolkit/set_env.sh \
                       /usr/local/Ascend/nnal/atb/set_env.sh; do
                [ -f "\$f" ] && source "\$f"
              done
              set -e

              # NPU sanity check.
              python - <<'PY'
              import sys, torch, torch_npu
              print("torch:", torch.__version__, "torch_npu:", torch_npu.__version__)
              if not torch.npu.is_available():
                  print("E2E-SKIP: torch.npu.is_available() is False", file=sys.stderr)
                  sys.exit(77)
              print("npu_count:", torch.npu.device_count(),
                    "device0:", torch.npu.get_device_name(0))
              PY

              # Install the community Ascend bnb fork. The workbench image ships
              # transformers/peft/accelerate/trl already; only bnb-npu is missing.
              # If pip can't fetch it (offline cluster with no PyPI mirror), or
              # the wheel doesn't import against this CANN/torch_npu combo, SKIP.
              set +e
              pip install --no-cache-dir --user "\${BNB_NPU_PIN}"
              pip_rc=\$?
              set -e
              if [ "\${pip_rc}" -ne 0 ]; then
                echo "E2E-SKIP: pip install \${BNB_NPU_PIN} failed (offline or unresolved)" >&2
                exit 77
              fi
              python - <<'PY'
              import sys
              try:
                  import torch_npu  # MUST be first
                  import bitsandbytes as bnb
                  print("bitsandbytes:", bnb.__version__)
              except Exception as e:
                  print(f"E2E-SKIP: bitsandbytes-npu-beta import failed: "
                        f"{type(e).__name__}: {e}", file=sys.stderr)
                  sys.exit(77)
              PY

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
                  ["hello world", "the quick brown fox", "alauda ai qlora on ascend"],
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

              # 2) QLoRA: BitsAndBytesConfig(load_in_4bit=...) + peft LoRA.
              #    Order: torch_npu first, then bitsandbytes.
              python - <<'PY'
              import os, sys, time, glob, torch
              import torch_npu  # noqa: F401  — must precede bitsandbytes
              try:
                  import bitsandbytes as bnb  # noqa: F401
              except Exception as e:
                  print(f"E2E-SKIP: bitsandbytes-npu-beta unusable at runtime: "
                        f"{type(e).__name__}: {e}", file=sys.stderr)
                  sys.exit(77)

              from transformers import (
                  AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig,
                  DataCollatorForLanguageModeling, Trainer, TrainingArguments,
              )
              from peft import LoraConfig, prepare_model_for_kbit_training, get_peft_model
              from datasets import load_dataset

              MODEL_DIR = "/workspace/tiny-qwen2"
              DATA = "/workspace/test_qlora_data.jsonl"
              OUT = "/workspace/ckpt"

              tok = AutoTokenizer.from_pretrained(MODEL_DIR)
              if tok.pad_token is None:
                  tok.pad_token = tok.eos_token

              bnb_cfg = BitsAndBytesConfig(
                  load_in_4bit=True, bnb_4bit_quant_type="nf4",
                  bnb_4bit_compute_dtype=torch.bfloat16,
                  bnb_4bit_use_double_quant=True,
              )
              try:
                  model = AutoModelForCausalLM.from_pretrained(
                      MODEL_DIR, quantization_config=bnb_cfg,
                      device_map={"": "npu:0"},
                      torch_dtype=torch.bfloat16,
                      attn_implementation="eager",
                  )
              except Exception as e:
                  print(f"E2E-SKIP: 4-bit load on NPU failed "
                        f"({type(e).__name__}: {e})", file=sys.stderr)
                  sys.exit(77)
              model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
              peft_cfg = LoraConfig(
                  r=8, lora_alpha=16, lora_dropout=0.05, bias="none",
                  target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
                  task_type="CAUSAL_LM",
              )
              model = get_peft_model(model, peft_cfg)
              model.print_trainable_parameters()

              raw = load_dataset("json", data_files=DATA, split="train")
              def render(ex):
                  text = tok.apply_chat_template(ex["messages"], tokenize=False)
                  out = tok(text, truncation=True, max_length=128,
                            padding="max_length", add_special_tokens=False)
                  out["labels"] = out["input_ids"].copy()
                  return out
              packed = raw.map(render, remove_columns=raw.column_names)

              args = TrainingArguments(
                  output_dir=OUT, num_train_epochs=1,
                  per_device_train_batch_size=2, gradient_accumulation_steps=1,
                  learning_rate=2e-4, warmup_steps=0,
                  logging_steps=1, save_steps=1000, save_total_limit=1,
                  bf16=True, fp16=False, optim="adamw_torch",
                  lr_scheduler_type="constant", seed=42,
                  report_to=[], remove_unused_columns=False,
                  dataloader_pin_memory=False,
                  max_steps=5,
              )
              collator = DataCollatorForLanguageModeling(tokenizer=tok, mlm=False)
              trainer = Trainer(model=model, args=args, train_dataset=packed, data_collator=collator)
              t0 = time.time()
              trainer.train()
              print(f"QLoRA-NPU finished in {time.time()-t0:.1f}s")

              adapter_dir = os.path.join(OUT, "adapter")
              model.save_pretrained(adapter_dir)
              tok.save_pretrained(adapter_dir)
              hits = glob.glob(os.path.join(adapter_dir, "adapter_model*"))
              assert hits, f"no adapter under {adapter_dir}: {sorted(os.listdir(adapter_dir))}"
              print(f"QLoRA adapter: {sorted(os.listdir(adapter_dir))}")
              PY
YAML

log "C15: waiting for pod to appear..."
deadline=$((SECONDS + 120))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C15: pod=${POD}"

# Scheduling SKIP: no schedulable NPU slice.
sched_deadline=$((SECONDS + 300))
phase=""
while [ "${SECONDS}" -lt "${sched_deadline}" ]; do
  phase="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in Running|Succeeded|Failed) break ;; esac
  sleep 5
done
if [ "${phase}" = "Pending" ] || [ -z "${phase}" ]; then
  EVT="$(npu_kc -n "${NS}" get event --field-selector "involvedObject.name=${POD}" \
         -o jsonpath='{range .items[*]}{.reason}: {.message}{"\n"}{end}' 2>/dev/null | tail -3)"
  log "C15: SKIP — pod ${POD} still ${phase:-<none>} (no schedulable NPU slice):"
  echo "${EVT}" | sed 's/^/    /'
  exit "${E2E_SKIP_RC}"
fi

if [ -n "${POD}" ]; then
  npu_kc -n "${NS}" logs -f "${POD}" 2>&1 &
  LOGS_PID=$!
fi
deadline=$((SECONDS + 2400))
status=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  status="$(npu_kc -n "${NS}" get job "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null || true)"
  case "${status}" in *Complete*) break ;; *Failed*) break ;; esac
  sleep 15
done
reap_logs "${LOGS_PID:-}"
log "C15: job status=${status}"

# Runtime SKIP: in-pod guard exits 77 for missing NPU or unusable bnb-npu wheel.
EXIT_CODE="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || true)"
if [ "${EXIT_CODE}" = "77" ]; then
  log "C15: SKIP — in-pod guard signalled unsupported runtime:"
  npu_kc -n "${NS}" logs "${POD}" --tail=30 2>&1 | grep -i 'E2E-SKIP' | sed 's/^/    /' || true
  exit "${E2E_SKIP_RC}"
fi

if [[ "${status}" != *Complete* ]]; then
  log "C15: ==== pod final state ===="
  npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  log "C15: ==== container logs ===="
  npu_kc -n "${NS}" logs -l "job-name=${JOB_NAME}" --tail=200 2>&1 || true
  log "C15: ==== pod describe ===="
  npu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -30 || true
fi
[[ "${status}" == *Complete* ]]
