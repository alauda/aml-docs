#!/usr/bin/env bash
# C8 — exercises fine-tune-with-trainer-v2-mindspeed-npu.ipynb.
# The notebook publishes a TrainingRuntime that converts HF weights → MCore,
# preprocesses an Alpaca-style dataset, and launches MindSpeed-LLM SFT on a
# Qwen3-0.6B checkpoint. Synthesising a Qwen3-architecture HF model that
# MindSpeed-LLM's checkpoint converter accepts is a heavier workstream
# (matching all 28 layers × 1024 hidden × 151936 vocab is the whole point of
# the converter). For this case we only verify the env half of the runtime —
# image pulls, CANN env can be sourced, torch_npu sees the NPU — using the
# same patched runtime YAML the notebook publishes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${NPU_NAMESPACE}"
RUNTIME="c8-mindspeed-llm-qwen3-npu-runtime"
IMAGE="${C8_IMAGE:-docker.io/alaudadockerhub/alauda-workbench-jupyter-pytorch-cann-py312-ubi9:v0.1.7}"

log "C8: applying TrainingRuntime ${RUNTIME} (env-smoke variant, image=${IMAGE})"
cat <<YAML | retry_apply npu_kc
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
      - name: node
        template:
          metadata:
            labels:
              trainer.kubeflow.org/trainjob-ancestor-step: trainer
          spec:
            backoffLimit: 0
            template:
              spec:
                # Notebook publishes \`schedulerName: hami-scheduler\` +
                # \`huawei.com/Ascend910B4\`; the dev NPU cluster uses the default
                # scheduler and bare \`huawei.com/Ascend910\` (see my_dev_env_new.md).
                runtimeClassName: ascend
                securityContext:
                  runAsNonRoot: true
                  runAsUser: 1001
                  runAsGroup: 0
                  fsGroup: 1000
                volumes:
                  - name: workspace
                    emptyDir: {}
                  - name: dshm
                    emptyDir: { medium: Memory, sizeLimit: 2Gi }
                containers:
                  - name: node
                    image: ${IMAGE}
                    imagePullPolicy: IfNotPresent
                    command: ["bash", "-lc"]
                    args:
                      - |
                        set -o pipefail
                        # Sourced exactly per the notebook runtime YAML.
                        set +e
                        for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
                          [ -f "\$f" ] && source "\$f"
                        done
                        set -e
                        python - <<'PY'
                        import importlib.metadata as md
                        import importlib.util
                        import torch
                        import torch_npu
                        for mod in ["torch", "torch_npu", "mindspeed", "mindspeed_llm"]:
                            assert importlib.util.find_spec(mod), f"missing {mod}"
                        print("torch:", torch.__version__)
                        print("torch_npu:", torch_npu.__version__)
                        try:
                            print("mindspeed:", md.version("mindspeed"))
                        except md.PackageNotFoundError:
                            print("mindspeed: dist not found (importable only)")
                        try:
                            print("mindspeed_llm:", md.version("mindspeed-llm"))
                        except md.PackageNotFoundError:
                            print("mindspeed_llm: dist not found (importable only)")
                        print("npu_count:", torch.npu.device_count())
                        assert torch.npu.is_available(), "NPU is not available"
                        x = torch.randn(512, 512).npu()
                        y = x @ x.T
                        print(f"matmul ok shape={tuple(y.shape)} mean={y.mean().item():.4f}")
                        PY
                    resources:
                      requests: { cpu: 200m, memory: 1Gi }
                      limits:
                        cpu: "2"
                        memory: 8Gi
                        huawei.com/Ascend910: "1"
                    securityContext:
                      allowPrivilegeEscalation: false
                      capabilities: { drop: [ALL] }
                      runAsNonRoot: true
                      seccompProfile: { type: RuntimeDefault }
                    volumeMounts:
                      - { name: workspace, mountPath: /mnt/workspace }
                      - { name: dshm, mountPath: /dev/shm }
YAML

log "C8: submitting TrainJob against ${RUNTIME}"
TJ_NAME=$(cat <<YAML | retry_create npu_kc -o jsonpath='{.metadata.name}'
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  generateName: c8-mindspeed-
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
log "C8: trainjob=${TJ_NAME}"

cleanup() {
  npu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C8: waiting for pod..."
deadline=$((SECONDS + 900))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(trainjob_pod npu_kc "${NS}" "${TJ_NAME}")"
  [ -n "${POD}" ] && break
  sleep 5
done
[ -z "${POD}" ] && { log "C8: no pod appeared"; exit 1; }
log "C8: pod=${POD}"

log "C8: waiting for terminal state..."
deadline=$((SECONDS + 1800))
ph=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  ph="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${ph}" in Succeeded|Failed) break ;; esac
  sleep 15
done
log "C8: pod phase=${ph}"
log "C8: ===== container logs ====="
npu_kc -n "${NS}" logs "${POD}" --tail=200 || true
log "C8: ===== end logs ====="
[ "${ph}" = "Succeeded" ]
