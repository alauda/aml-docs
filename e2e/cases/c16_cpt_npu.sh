#!/usr/bin/env bash
# C16 — Continued pre-training (CPT) on a Huawei Ascend NPU using ONLY mainline
# transformers + torch_npu. Companion of C14 (which uses training_hub on CUDA):
# training_hub doesn't run on Ascend, so the recipe uses transformers.Trainer
# with bf16 + adamw_torch on `torch.npu`. Generates a tiny synthetic Qwen2 base
# model + a synthetic raw-text corpus in-Pod so it needs no external download.
#
# Image: the same PyTorch CANN workbench image C7/C8 use. CANN env is sourced
# per the C8 pattern. NPU is requested via ${NPU_RESOURCE_NAME} (e.g.
# huawei.com/Ascend910B4), quantity ${NPU_RESOURCE_VALUE:-1}.
#
# SKIP (rc=77) conditions:
#   * NPU_NAMESPACE or NPU_RESOURCE_NAME not set (opt-in — see run_all.sh);
#   * the NPU slice cannot be scheduled (captured scheduler event);
#   * the in-Pod NPU sanity check fails (torch.npu.is_available() is False).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env NPU_NAMESPACE "namespace for NPU e2e resources"
require_env NPU_RESOURCE_NAME "extended resource name for one NPU, for example huawei.com/Ascend910B4"
NS="${NPU_NAMESPACE}"
JOB_NAME="c16-cpt-npu-$(printf '%05x' $$)"
IMAGE="${C16_IMAGE:-docker.io/alaudadockerhub/alauda-workbench-jupyter-pytorch-cann-py312-ubi9:v0.1.7}"
IMAGE_PULL_SECRET="${C16_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
NPU_RESOURCE_VALUE="${NPU_RESOURCE_VALUE:-1}"
NPU_MEMORY_RESOURCE_NAME="${NPU_MEMORY_RESOURCE_NAME:-}"
NPU_MEMORY_RESOURCE_VALUE="${NPU_MEMORY_RESOURCE_VALUE:-8192}"
NPU_RUNTIME_CLASS="${NPU_RUNTIME_CLASS:-}"

cleanup() {
  npu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C16: submitting Job ${JOB_NAME} (image=${IMAGE})"

cat <<YAML | mirror_dockerhub "${NPU_DH_MIRROR}" | npu_kc -n "${NS}" create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  labels:
    e2e.alauda.io/case: c16
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c16
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

              # NPU sanity check — if torch_npu can't see an NPU, SKIP (77).
              python - <<'PY'
              import sys
              import torch
              import torch_npu  # noqa: F401 — side-effect: registers torch.npu
              print("torch:", torch.__version__, "torch_npu:", torch_npu.__version__)
              if not torch.npu.is_available():
                  print("E2E-SKIP: torch.npu.is_available() is False", file=sys.stderr)
                  sys.exit(77)
              print("npu_count:", torch.npu.device_count(),
                    "device0:", torch.npu.get_device_name(0))
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
                  ["hello world", "the quick brown fox", "alauda ai continued pretraining on ascend"],
                  vocab_size=512, min_frequency=1,
                  special_tokens=["<pad>", "<s>", "</s>", "<unk>"],
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
              Qwen2ForCausalLM(cfg).save_pretrained(MODEL_DIR)

              # 2) Synthetic RAW-TEXT corpus — one document per line under "text".
              data_path = "/workspace/test_cpt_data.jsonl"
              docs = [
                  "Alauda AI is an MLOps platform that runs fine-tuning and inference on Kubernetes.",
                  "Continued pre-training keeps the causal-LM objective and updates every weight.",
                  "Huawei Ascend NPUs are programmed through the CANN runtime and torch_npu.",
                  "A CPT run should be followed by SFT to restore instruction-following behaviour.",
              ] * 8
              with open(data_path, "w") as f:
                  for d in docs:
                      json.dump({"text": d}, f); f.write("\n")
              print(f"prepared base model {MODEL_DIR} and raw-text corpus {data_path}")
              PY

              # 3) Continued pre-training via transformers.Trainer on torch_npu.
              python - <<'PY'
              import os, time, torch
              import torch_npu  # noqa: F401
              from transformers import (
                  AutoModelForCausalLM, AutoTokenizer,
                  DataCollatorForLanguageModeling,
                  Trainer, TrainingArguments,
              )
              from datasets import load_dataset

              MODEL_DIR = "/workspace/tiny-qwen2"
              DATA = "/workspace/test_cpt_data.jsonl"
              OUT = "/workspace/ckpt"
              BLOCK = 128

              tok = AutoTokenizer.from_pretrained(MODEL_DIR)
              if tok.pad_token is None:
                  tok.pad_token = tok.eos_token
              model = AutoModelForCausalLM.from_pretrained(
                  MODEL_DIR, torch_dtype=torch.bfloat16, attn_implementation="eager",
              ).to("npu")
              model.gradient_checkpointing_enable()

              raw = load_dataset("json", data_files=DATA, split="train")
              def tokenize(batch):
                  return tok(batch["text"], add_special_tokens=False)
              tokenized = raw.map(tokenize, batched=True, remove_columns=raw.column_names)
              def group_texts(examples):
                  concat = {k: sum(examples[k], []) for k in examples.keys()}
                  n = (len(concat["input_ids"]) // BLOCK) * BLOCK
                  out = {k: [t[i:i+BLOCK] for i in range(0, n, BLOCK)]
                         for k, t in concat.items()}
                  out["labels"] = [ids.copy() for ids in out["input_ids"]]
                  return out
              packed = tokenized.map(group_texts, batched=True)
              print("packed chunks:", len(packed), "of", BLOCK, "tokens")

              args = TrainingArguments(
                  output_dir=OUT, num_train_epochs=1,
                  per_device_train_batch_size=2, gradient_accumulation_steps=1,
                  learning_rate=5e-6, warmup_steps=0,
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
              print(f"CPT-NPU finished in {time.time()-t0:.1f}s")

              hf_dir = os.path.join(OUT, "hf_format")
              trainer.save_model(hf_dir)
              tok.save_pretrained(hf_dir)
              files = sorted(os.listdir(hf_dir))
              print("saved:", hf_dir, files)
              # Any of these is a valid HF checkpoint marker; be liberal so a
              # transformers rename doesn't break the assertion.
              wanted = {"model.safetensors", "pytorch_model.bin", "adapter_model.safetensors"}
              assert wanted & set(files), f"no HF checkpoint under {hf_dir}: {files}"
              PY
YAML

log "C16: waiting for pod to appear..."
deadline=$((SECONDS + 120))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C16: pod=${POD}"

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
  log "C16: SKIP — pod ${POD} still ${phase:-<none>} (no schedulable NPU slice):"
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
log "C16: job status=${status}"

# Runtime SKIP: in-pod guard exits 77 if the NPU is not visible.
EXIT_CODE="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || true)"
if [ "${EXIT_CODE}" = "77" ]; then
  log "C16: SKIP — in-pod guard signalled no NPU:"
  npu_kc -n "${NS}" logs "${POD}" --tail=20 2>&1 | grep -i 'E2E-SKIP' | sed 's/^/    /' || true
  exit "${E2E_SKIP_RC}"
fi

if [[ "${status}" != *Complete* ]]; then
  log "C16: ==== pod final state ===="
  npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o wide 2>&1 | tail -5 || true
  log "C16: ==== container logs ===="
  npu_kc -n "${NS}" logs -l "job-name=${JOB_NAME}" --tail=200 2>&1 || true
  log "C16: ==== pod describe ===="
  npu_kc -n "${NS}" describe pod -l "job-name=${JOB_NAME}" 2>&1 | tail -30 || true
fi
[[ "${status}" == *Complete* ]]
