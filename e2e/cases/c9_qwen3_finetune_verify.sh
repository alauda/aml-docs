#!/usr/bin/env bash
# C9 — exercises the env half of qwen3_finetune_verify.ipynb.
# The notebook expects a real Qwen3-8B HF checkpoint at /opt/app-root/src/models/Qwen3-8B
# (~16 GiB) which isn't materially synthesisable for an e2e smoke. This case
# pulls the PyTorch CANN workbench image the notebook documents
# (`alauda-workbench-jupyter-pytorch-cann-py312-ubi9:v0.1.7`) and verifies the
# same env check the notebook's cell 1 performs: torch + torch_npu + MindSpeed +
# MindSpeed-LLM imports, NPU count, and a matmul on the NPU. The HF→MCore
# conversion + training cells need real model weights and are out of scope.
#
# C10 (qwen25_pretrain_verify.ipynb) shares the same workbench image and env
# contract; this case implicitly verifies C10's env too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env NPU_NAMESPACE "namespace for NPU e2e resources"
require_env NPU_RESOURCE_NAME "extended resource name for one NPU, for example huawei.com/Ascend910B4"
NS="${NPU_NAMESPACE}"
JOB_NAME="c9-pytorch-cann-smoke-$(printf '%05x' $$)"
IMAGE="${C9_IMAGE:-docker.io/alaudadockerhub/alauda-workbench-jupyter-pytorch-cann-py312-ubi9:v0.1.7}"
IMAGE_PULL_SECRET="${C9_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
NPU_RESOURCE_VALUE="${NPU_RESOURCE_VALUE:-1}"
NPU_MEMORY_RESOURCE_NAME="${NPU_MEMORY_RESOURCE_NAME:-}"
NPU_MEMORY_RESOURCE_VALUE="${NPU_MEMORY_RESOURCE_VALUE:-8192}"
NPU_RUNTIME_CLASS="${NPU_RUNTIME_CLASS:-}"

cleanup() {
  npu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C9: submitting Job ${JOB_NAME} (image=${IMAGE})"
cat <<YAML | mirror_dockerhub "${NPU_DH_MIRROR}" | retry_create npu_kc >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NS}
  labels:
    e2e.alauda.io/case: c9
spec:
  backoffLimit: 0
  template:
    metadata:
      labels: { e2e.alauda.io/case: c9 }
    spec:
      restartPolicy: Never
$(yaml_scalar_field 6 runtimeClassName "${NPU_RUNTIME_CLASS}")
$(yaml_image_pull_secrets 6 "${IMAGE_PULL_SECRET}")
      securityContext: { runAsNonRoot: true, runAsUser: 1001, runAsGroup: 0, fsGroup: 1000 }
      containers:
        - name: probe
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: [ALL] }
            runAsNonRoot: true
            seccompProfile: { type: RuntimeDefault }
          resources:
            requests: { cpu: 200m, memory: 1Gi }
            limits:
              cpu: "2"
              memory: 8Gi
$(yaml_resource_limit 14 "${NPU_RESOURCE_NAME}" "${NPU_RESOURCE_VALUE}")
$(yaml_resource_limit 14 "${NPU_MEMORY_RESOURCE_NAME}" "${NPU_MEMORY_RESOURCE_VALUE}")
          command: [bash, -lc]
          args:
            - |
              set -o pipefail
              # Match the notebook cell 1 source pattern exactly.
              set +e
              for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
                [ -f "\$f" ] && source "\$f"
              done
              set -e
              python - <<'PY'
              import importlib.metadata as md
              import importlib.util
              import warnings
              # The notebook silences torch_npu's import-time deprecation
              # warnings; mirror that so the e2e log stays focused on real errors.
              warnings.filterwarnings('ignore', category=DeprecationWarning)
              warnings.filterwarnings('ignore', category=ImportWarning)
              warnings.filterwarnings('ignore', category=UserWarning)
              import torch, torch_npu
              for mod in ["torch", "torch_npu", "mindspeed", "mindspeed_llm"]:
                  assert importlib.util.find_spec(mod), f"missing {mod}"
              print("torch:", torch.__version__)
              print("torch_npu:", torch_npu.__version__)
              nproc = torch.npu.device_count()
              print("npu_count:", nproc)
              for i in range(nproc):
                  print(f"  NPU {i}: {torch.npu.get_device_name(i)}")
              assert torch.npu.is_available(), "NPU is not available"
              x = torch.randn(512, 512).npu()
              y = x @ x.T
              print(f"matmul ok shape={tuple(y.shape)} mean={y.mean().item():.4f}")
              PY
YAML

log "C9: waiting for pod..."
deadline=$((SECONDS + 600))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C9: pod=${POD}"

deadline=$((SECONDS + 1800))
ph=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  ph="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${ph}" in Succeeded|Failed) break ;; esac
  sleep 15
done
log "C9: pod phase=${ph}"
log "C9: ===== container logs ====="
npu_kc -n "${NS}" logs "${POD}" --tail=200 || true
log "C9: ===== end logs ====="
[ "${ph}" = "Succeeded" ]
