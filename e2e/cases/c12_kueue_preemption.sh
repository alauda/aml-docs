#!/usr/bin/env bash
# C12 — exercises preemptible-trainjobs-with-kueue.mdx end-to-end.
#
# What it covers:
#   1. Builds a two-CQ cohort: inference owns the GPU quota, training
#      borrows it (asset cluster-queues.yaml + workload-priorities.yaml).
#   2. Submits a low-priority TrainJob; waits for it to actually train and
#      land at least one checkpoint on the RWX PVC.
#   3. Submits a high-priority preemptor; asserts the training Workload
#      reaches `Preempted=True` with reason `InCohortReclamation`.
#   4. Lets the preemptor finish; asserts the training Workload is
#      re-admitted and the resumed trainer logs the
#      "[checkpoint] resuming from ..." line.
#
# The TrainingRuntime uses plain HuggingFace Trainer (not LlamaFactory),
# because LF's bootstrap path was found to hang on toy models on
# Tesla P100 + HAMI in dev; HF Trainer reproduces the same checkpoint
# semantics with sub-second per-step time on the same hardware.
#
# This case mutates cluster-scoped Kueue objects (ClusterQueue,
# ResourceFlavor, WorkloadPriorityClass). The trap below removes everything
# it created so a re-run is clean.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${GPU_NAMESPACE}"
RUN_ID="$(printf '%05x' $$)-$(date -u +%s)"

# Cluster-scoped names are shared across runs intentionally — the trap deletes
# them on exit so concurrent runs would clash anyway. The PVC is per-run.
CQ_INF="c12-inference-cq"
CQ_TRAIN="c12-training-cq"
LQ_INF="c12-inference-lq"
LQ_TRAIN="c12-training-lq"
WPC_INF="c12-inference-prio"
WPC_TRAIN="c12-training-prio"
FLAVOR="c12-default"
RUNTIME="c12-checkpoint-runtime-${RUN_ID}"
PVC_NAME="c12-ckpt-${RUN_ID}"
TRAIN_LABEL="e2e.alauda.io/c12-run=${RUN_ID}"

# Same harbor image C5/C6 already use — guaranteed cached on the GPU node.
IMAGE="${LF_IMAGE:-build-harbor.alauda.cn/mlops/llamafactory0.9-cu126-amd64:v0.1.0-build.20260603021903}"

# --- Preflight: Kueue must be installed; skip otherwise. -----------------
if ! gpu_kc api-resources --api-group=kueue.x-k8s.io 2>/dev/null | grep -q clusterqueues; then
  log "C12: kueue.x-k8s.io API group not present — install Kueue (see preemptible-trainjobs-with-kueue.mdx) and re-run"
  exit 77
fi

cleanup() {
  log "C12: cleanup"
  gpu_kc -n "${NS}" delete trainjob -l "${TRAIN_LABEL}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete job      -l "${TRAIN_LABEL}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete trainingruntime "${RUNTIME}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete pvc "${PVC_NAME}" --ignore-not-found --wait=false || true
  gpu_kc -n "${NS}" delete localqueue "${LQ_INF}" "${LQ_TRAIN}" --ignore-not-found --wait=false || true
  gpu_kc delete clusterqueue "${CQ_INF}" "${CQ_TRAIN}" --ignore-not-found --wait=false || true
  gpu_kc delete resourceflavor "${FLAVOR}" --ignore-not-found --wait=false || true
  gpu_kc delete workloadpriorityclass "${WPC_INF}" "${WPC_TRAIN}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

# --- Step 1: cohort + queues + priorities. -------------------------------
# Quotas are sized for one Tesla P100 + HAMI (gpucores 50%, 4 GiB GPU mem):
# both inference and training Workloads each ask for that slice, so the
# inference reclaim path empties exactly one borrowed training slot.
log "C12: applying cohort (CQ ${CQ_INF}, ${CQ_TRAIN}; flavor ${FLAVOR})"
cat <<YAML | retry_apply gpu_kc
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata: { name: ${FLAVOR} }
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata: { name: ${CQ_INF} }
spec:
  cohortName: c12-shared-${RUN_ID}
  namespaceSelector: {}
  preemption:
    reclaimWithinCohort: Any
    borrowWithinCohort: { policy: LowerPriority, maxPriorityThreshold: 100 }
    withinClusterQueue: LowerPriority
  resourceGroups:
    - coveredResources: ["cpu", "memory", "nvidia.com/gpualloc", "nvidia.com/gpucores", "nvidia.com/gpumem"]
      flavors:
        - name: ${FLAVOR}
          resources:
            - { name: cpu,                 nominalQuota: "4",    borrowingLimit: "0" }
            - { name: memory,              nominalQuota: 8Gi,    borrowingLimit: 0 }
            - { name: nvidia.com/gpualloc, nominalQuota: "1",    borrowingLimit: "0" }
            - { name: nvidia.com/gpucores, nominalQuota: "50",   borrowingLimit: "0" }
            - { name: nvidia.com/gpumem,   nominalQuota: "4096", borrowingLimit: "0" }
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata: { name: ${CQ_TRAIN} }
spec:
  cohortName: c12-shared-${RUN_ID}
  namespaceSelector: {}
  preemption:
    reclaimWithinCohort: Any
    withinClusterQueue: LowerPriority
  resourceGroups:
    - coveredResources: ["cpu", "memory", "nvidia.com/gpualloc", "nvidia.com/gpucores", "nvidia.com/gpumem"]
      flavors:
        - name: ${FLAVOR}
          resources:
            - { name: cpu,                 nominalQuota: "0",    borrowingLimit: "4" }
            - { name: memory,              nominalQuota: 0,      borrowingLimit: 8Gi }
            - { name: nvidia.com/gpualloc, nominalQuota: "0",    borrowingLimit: "1" }
            - { name: nvidia.com/gpucores, nominalQuota: "0",    borrowingLimit: "50" }
            - { name: nvidia.com/gpumem,   nominalQuota: "0",    borrowingLimit: "4096" }
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata: { name: ${WPC_INF} }
value: 1000
description: "C12 — online inference; preempts training to reclaim quota"
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata: { name: ${WPC_TRAIN} }
value: 10
description: "C12 — opportunistic training; preemptible"
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata: { name: ${LQ_INF},   namespace: ${NS} }
spec: { clusterQueue: ${CQ_INF} }
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata: { name: ${LQ_TRAIN}, namespace: ${NS} }
spec: { clusterQueue: ${CQ_TRAIN} }
YAML

log "C12: provisioning checkpoint PVC ${PVC_NAME}"
cat <<YAML | retry_apply gpu_kc
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: ${PVC_NAME}, namespace: ${NS} }
spec:
  storageClassName: cephfs
  accessModes: ["ReadWriteMany"]
  resources: { requests: { storage: 1Gi } }
YAML

# --- Step 2: checkpoint-aware TrainingRuntime. ---------------------------
# Identical recipe to assets/kueue/preemption/training-runtime.yaml, but
# inlined here so re-runs don't depend on the file being fetched from
# elsewhere. HuggingFace Trainer auto-resumes from the newest
# checkpoint-N/ in CKPT_DIR if we pass it to .train(resume_from_checkpoint=).
log "C12: applying TrainingRuntime ${RUNTIME}"
cat <<YAML | retry_apply gpu_kc
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainingRuntime
metadata:
  name: ${RUNTIME}
  namespace: ${NS}
  labels: { trainer.kubeflow.org/framework: torch }
spec:
  mlPolicy:
    numNodes: 1
    torch: { numProcPerNode: auto }
  template:
    spec:
      replicatedJobs:
        - name: node
          template:
            metadata:
              labels: { trainer.kubeflow.org/trainjob-ancestor-step: trainer }
            spec:
              backoffLimit: 0
              template:
                spec:
                  terminationGracePeriodSeconds: 60
                  nodeSelector: { kubernetes.io/hostname: 192.168.138.15 }
                  imagePullSecrets: [{ name: harbor-mlops-regcred }]
                  securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
                  volumes:
                    - { name: workspace, emptyDir: {} }
                    - { name: ckpt, persistentVolumeClaim: { claimName: ${PVC_NAME} } }
                    - { name: dshm, emptyDir: { medium: Memory, sizeLimit: 512Mi } }
                  containers:
                    - name: node
                      image: ${IMAGE}
                      env:
                        - { name: PYTHONUNBUFFERED, value: "1" }
                        - { name: MPLCONFIGDIR, value: /workspace/matplotlib }
                        - { name: XDG_CACHE_HOME, value: /workspace/cache }
                        - { name: CKPT_DIR, value: /mnt/ckpt/run }
                        # Enough epochs that even on Tesla P100 the run lasts
                        # well past the preemption + resume window — the test
                        # is on Kueue + checkpoint semantics, not throughput.
                        - { name: NUM_TRAIN_EPOCHS, value: "1500" }
                      volumeMounts:
                        - { mountPath: /workspace, name: workspace }
                        - { mountPath: /mnt/ckpt,  name: ckpt }
                        - { mountPath: /dev/shm,   name: dshm }
                      command: [bash, -ec]
                      args:
                        - |
                          set -ex
                          mkdir -p /workspace/matplotlib /workspace/cache /workspace/stubs/deepspeed
                          # Catalog image ships CUDA runtime but no nvcc;
                          # accelerate.utils.other.extract_model_from_parallel
                          # eagerly imports DeepSpeedEngine on save, and the
                          # real deepspeed fails op_builder.is_compatible()
                          # without CUDA_HOME. Stubbing the module sidesteps it.
                          cat >/workspace/stubs/deepspeed/__init__.py <<'PY'
                          class DeepSpeedEngine: ...
                          PY
                          export PYTHONPATH=/workspace/stubs:\${PYTHONPATH:-}
                          mkdir -p "\${CKPT_DIR}"
                          python - <<'PY'
                          import os, glob, torch
                          from datasets import Dataset
                          from transformers import (GPT2TokenizerFast, Qwen2Config, Qwen2ForCausalLM,
                                                    Trainer, TrainingArguments)
                          from tokenizers import ByteLevelBPETokenizer
                          torch.manual_seed(0)
                          base = "/workspace/base"
                          os.makedirs(base, exist_ok=True)
                          bpe = ByteLevelBPETokenizer()
                          bpe.train_from_iterator(["hello","world","alauda ai","trainer","kueue preempt"],
                              vocab_size=512, min_frequency=1, special_tokens=["<pad>","<s>","</s>","<unk>"])
                          bpe.save_model(base)
                          tok = GPT2TokenizerFast(vocab_file=f"{base}/vocab.json", merges_file=f"{base}/merges.txt",
                              unk_token="<unk>", bos_token="<s>", eos_token="</s>", pad_token="<pad>")
                          tok.save_pretrained(base)
                          cfg = Qwen2Config(vocab_size=tok.vocab_size+4, hidden_size=32, num_hidden_layers=2,
                              num_attention_heads=2, num_key_value_heads=2, intermediate_size=64,
                              max_position_embeddings=64, rope_theta=10000.0, tie_word_embeddings=True)
                          Qwen2ForCausalLM(cfg).save_pretrained(base)
                          texts = ["who are you? i am alauda ai"] * 32
                          ds = Dataset.from_dict({"input_ids": [
                              tok.encode(t, padding="max_length", max_length=16, truncation=True)
                              for t in texts]})
                          ds = ds.map(lambda x: {"labels": x["input_ids"]}, batched=False)
                          ckpt_dir = os.environ["CKPT_DIR"]
                          ckpts = sorted(glob.glob(f"{ckpt_dir}/checkpoint-*"),
                                          key=lambda p: int(p.rsplit("-",1)[1]))
                          resume = ckpts[-1] if ckpts else None
                          if resume:
                              print(f"[checkpoint] resuming from {resume}", flush=True)
                          else:
                              print("[checkpoint] no prior checkpoint, starting fresh", flush=True)
                          model = Qwen2ForCausalLM.from_pretrained(base).to("cuda")
                          args = TrainingArguments(
                              output_dir=ckpt_dir,
                              per_device_train_batch_size=2,
                              num_train_epochs=int(os.environ.get("NUM_TRAIN_EPOCHS","200")),
                              logging_steps=5,
                              save_strategy="steps", save_steps=4, save_total_limit=2,
                              report_to=[], bf16=False, fp16=False,
                              dataloader_num_workers=0, remove_unused_columns=False)
                          trainer = Trainer(model=model, args=args, train_dataset=ds, tokenizer=tok)
                          trainer.train(resume_from_checkpoint=resume)
                          print(f"[checkpoint] done. ckpts={sorted(os.listdir(ckpt_dir))}", flush=True)
                          PY
                      resources:
                        requests: { cpu: "1", memory: 2Gi }
                        limits:
                          cpu: "2"
                          memory: 4Gi
                          nvidia.com/gpualloc: 1
                          nvidia.com/gpucores: 50
                          nvidia.com/gpumem: "4096"
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities: { drop: [ALL] }
                        runAsNonRoot: true
                        seccompProfile: { type: RuntimeDefault }
YAML

# --- Step 3: low-priority TrainJob. --------------------------------------
log "C12: submitting low-priority TrainJob"
TJ_NAME=$(cat <<YAML | retry_create gpu_kc -o jsonpath='{.metadata.name}'
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  generateName: c12-training-
  namespace: ${NS}
  labels:
    kueue.x-k8s.io/queue-name: ${LQ_TRAIN}
    kueue.x-k8s.io/priority-class: ${WPC_TRAIN}
    e2e.alauda.io/case: c12
    e2e.alauda.io/c12-run: "${RUN_ID}"
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
log "C12: trainjob=${TJ_NAME}"

# --- Step 4: wait until training is actually checkpointing. --------------
log "C12: waiting for trainer pod"
deadline=$((SECONDS + 480))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}" node)"
  [ -n "${POD}" ] && break
  sleep 5
done
[ -n "${POD}" ] || { log "C12: trainer pod did not appear"; exit 1; }
log "C12: trainer pod=${POD}"

# Poll the PVC directly via kubectl exec — `kubectl logs` is unreliable here
# because HF Trainer's tqdm progress bar overwrites the "Saving model
# checkpoint to" line, so a grep on logs misses every save.
log "C12: waiting for first checkpoint on PVC"
deadline=$((SECONDS + 480))
have_ckpt=0
while [ "${SECONDS}" -lt "${deadline}" ]; do
  if gpu_kc -n "${NS}" exec "${POD}" -c node -- sh -c 'ls -d /mnt/ckpt/run/checkpoint-* 2>/dev/null | head -1' 2>/dev/null | grep -q checkpoint-; then
    have_ckpt=1
    break
  fi
  sleep 5
done
[ "${have_ckpt}" = "1" ] || { log "C12: no checkpoint-N/ on PVC within deadline"; gpu_kc -n "${NS}" logs "${POD}" --tail=40 || true; exit 1; }
log "C12: checkpoint visible on PVC"

# --- Step 5: high-priority preemptor. -----------------------------------
log "C12: submitting high-priority preemptor Job"
INF_JOB=$(cat <<YAML | retry_create gpu_kc -o jsonpath='{.metadata.name}'
apiVersion: batch/v1
kind: Job
metadata:
  generateName: c12-inference-
  namespace: ${NS}
  labels:
    kueue.x-k8s.io/queue-name: ${LQ_INF}
    kueue.x-k8s.io/priority-class: ${WPC_INF}
    e2e.alauda.io/case: c12
    e2e.alauda.io/c12-run: "${RUN_ID}"
spec:
  ttlSecondsAfterFinished: 60
  template:
    metadata:
      labels:
        e2e.alauda.io/case: c12
        e2e.alauda.io/c12-run: "${RUN_ID}"
    spec:
      restartPolicy: Never
      nodeSelector: { kubernetes.io/hostname: 192.168.138.15 }
      imagePullSecrets: [{ name: harbor-mlops-regcred }]
      securityContext: { runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534 }
      containers:
        - name: serve
          image: ${IMAGE}
          command: [bash, -ec]
          args:
            - |
              set -ex
              python -c "import torch; print('cuda=', torch.cuda.is_available(), 'dev=', torch.cuda.device_count())"
              # Hold the GPU for ~80s — long enough to make the preemption
              # observable, short enough that training has time to be
              # re-admitted and resume before the e2e deadline.
              python -c "
              import torch, time
              x = torch.randn(512, 512, device='cuda')
              for i in range(40):
                  y = x @ x.T
                  if i % 5 == 0: print('inference tick', i, 'mean=%.4f' % y.mean().item(), flush=True)
                  time.sleep(2)
              print('inference done')"
          resources:
            requests: { cpu: "1", memory: 2Gi }
            limits:
              cpu: "2"
              memory: 4Gi
              nvidia.com/gpualloc: 1
              nvidia.com/gpucores: 50
              nvidia.com/gpumem: "4096"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: [ALL] }
            runAsNonRoot: true
            seccompProfile: { type: RuntimeDefault }
YAML
)
log "C12: inference job=${INF_JOB}"

# --- Step 6: assert training Workload was preempted. ---------------------
# The Workload is owned by the TrainJob (`generateName: c12-training-`), so
# any Workload whose name matches that prefix and has `Preempted=True` is
# the training side of the cohort reclamation.
log "C12: waiting for training Workload to be Preempted"
deadline=$((SECONDS + 300))
preempted_wl=""
preempt_reason=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  # iterate names; for each, dump the Preempted condition status+reason
  for wl in $(gpu_kc -n "${NS}" get workload -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    case "${wl}" in
      *${TJ_NAME}*) ;;
      *) continue ;;
    esac
    line="$(gpu_kc -n "${NS}" get workload "${wl}" -o jsonpath='{range .status.conditions[?(@.type=="Preempted")]}{.status}:{.reason}{end}' 2>/dev/null || true)"
    if [ "${line%%:*}" = "True" ]; then
      preempted_wl="${wl}"
      preempt_reason="${line#*:}"
      break 2
    fi
  done
  sleep 5
done
[ -n "${preempted_wl}" ] || { log "C12: training Workload was not preempted within deadline"; gpu_kc -n "${NS}" get workload -o yaml | tail -80; exit 1; }
log "C12: preempted workload=${preempted_wl} reason=${preempt_reason}"
[ "${preempt_reason}" = "InCohortReclamation" ] || { log "C12: preemption reason was ${preempt_reason}, expected InCohortReclamation"; exit 1; }

# --- Step 7: wait for inference to finish + training to re-admit. -------
log "C12: waiting for inference Job to complete"
deadline=$((SECONDS + 300))
done_n=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  done_n="$(gpu_kc -n "${NS}" get job "${INF_JOB}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  [ "${done_n}" = "1" ] && break
  sleep 10
done
[ "${done_n}" = "1" ] || { log "C12: inference job did not complete"; exit 1; }
log "C12: inference job complete; waiting for training re-admission"

# After inference frees its quota Kueue re-admits the training Workload;
# Trainer v2 then spawns a fresh trainer pod under the same TrainJob.
deadline=$((SECONDS + 300))
RESUME_POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  candidate="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}" node)"
  if [ -n "${candidate}" ] && [ "${candidate}" != "${POD}" ]; then
    RESUME_POD="${candidate}"
    break
  fi
  sleep 5
done
[ -n "${RESUME_POD}" ] || { log "C12: no resumed trainer pod within deadline"; exit 1; }
log "C12: resumed trainer pod=${RESUME_POD}"

# --- Step 8: assert the resumed pod actually loaded a checkpoint. -------
log "C12: waiting for resume-from-checkpoint log line"
deadline=$((SECONDS + 300))
seen_resume=0
while [ "${SECONDS}" -lt "${deadline}" ]; do
  if gpu_kc -n "${NS}" logs "${RESUME_POD}" 2>/dev/null | grep -q "\[checkpoint\] resuming from"; then
    seen_resume=1
    break
  fi
  sleep 10
done
[ "${seen_resume}" = "1" ] || { log "C12: resumed pod did not log a checkpoint resume"; gpu_kc -n "${NS}" logs "${RESUME_POD}" --tail=60 || true; gpu_kc -n "${NS}" describe pod "${RESUME_POD}" 2>&1 | tail -20 || true; exit 1; }

log "C12: end-to-end preemption + resume verified"
