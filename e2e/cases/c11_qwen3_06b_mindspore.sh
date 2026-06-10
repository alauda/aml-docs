#!/usr/bin/env bash
# C11 — exercises the env half of qwen3_0.6b_finetune_verify.ipynb.
# The notebook targets the MindSpore CANN workbench image
# (`alauda-workbench-jupyter-mindspore-cann-py312-ubi9:v0.1.7`) and runs the
# upstream Qwen3 MindSpore SFT recipe end-to-end. The full pipeline needs a
# Qwen3-0.6B HF checkpoint and the bundled MindSpeed-Core-MS source tree, so
# this case only verifies the env contract: mindspore + msadapter + mindspeed +
# mindspeed_llm import, MINDSPEED_CORE_MS_PATH is populated, and NPU is visible.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${NPU_NAMESPACE}"
JOB_NAME="c11-mindspore-cann-smoke-$(printf '%05x' $$)"
IMAGE="${C11_IMAGE:-docker.io/alaudadockerhub/alauda-workbench-jupyter-mindspore-cann-py312-ubi9:v0.1.7}"

cleanup() {
  npu_kc -n "${NS}" delete job "${JOB_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C11: submitting Job ${JOB_NAME} (image=${IMAGE})"
cat <<YAML | retry_create npu_kc >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NS}
  labels:
    e2e.alauda.io/case: c11
spec:
  backoffLimit: 0
  template:
    metadata:
      labels: { e2e.alauda.io/case: c11 }
    spec:
      restartPolicy: Never
      runtimeClassName: ascend
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
              huawei.com/Ascend910: "1"
          command: [bash, -lc]
          args:
            - |
              set -o pipefail
              set +e
              for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
                [ -f "\$f" ] && source "\$f"
              done
              # mindspore + msadapter are pip-installed in site-packages, but
              # mindspeed / mindspeed_llm / megatron live in the bundled source
              # tree under /opt/app-root/share/MindSpeed-Core-MS/. set_path.sh
              # prepends MindSpeed-LLM/ ahead of MindSpeed/ so the patched
              # (msadapter-aware) copy of \`mindspeed\` wins — do NOT layer extra
              # PYTHONPATH entries on top of it, that inverts the order and
              # loads the upstream-unpatched MindSpeed/ which expects real torch.
              export MINDSPEED_CORE_MS_PATH=/opt/app-root/share/MindSpeed-Core-MS
              for cand in \
                "\$MINDSPEED_CORE_MS_PATH/tests/scripts/set_path.sh" \
                "\$MINDSPEED_CORE_MS_PATH/MSAdapter/scripts/set_path.sh"; do
                [ -f "\$cand" ] && source "\$cand" && break
              done
              set -e
              python - <<'PY'
              import importlib.util, os, warnings
              warnings.filterwarnings('ignore', category=DeprecationWarning)
              warnings.filterwarnings('ignore', category=ImportWarning)
              warnings.filterwarnings('ignore', category=UserWarning)
              warnings.filterwarnings('ignore', category=FutureWarning)
              import mindspore as ms
              import msadapter
              import mindspeed
              import mindspeed_llm
              for mod in ["mindspore", "msadapter", "mindspeed", "mindspeed_llm"]:
                  assert importlib.util.find_spec(mod), f"missing {mod}"
              print("mindspore:", ms.__version__)
              print("msadapter:", getattr(msadapter, "__version__", "<no __version__>"))
              try:
                  print("mindspeed:", mindspeed.__version__)
              except AttributeError:
                  print("mindspeed: imported")
              try:
                  print("mindspeed_llm:", mindspeed_llm.__version__)
              except AttributeError:
                  print("mindspeed_llm: imported")
              core_ms = os.environ.get("MINDSPEED_CORE_MS_PATH", "/opt/app-root/share/MindSpeed-Core-MS")
              print(f"MINDSPEED_CORE_MS_PATH={core_ms} exists={os.path.isdir(core_ms)}")
              # MindSpore device count via context.
              ms.set_context(device_target="Ascend")
              from mindspore import ops, Tensor
              x = ms.numpy.ones((128, 128))
              y = ops.matmul(x, x.T)
              print(f"mindspore matmul ok shape={y.shape} mean={float(y.mean()):.4f}")
              PY
YAML

log "C11: waiting for pod..."
deadline=$((SECONDS + 600))
POD=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  POD="$(npu_kc -n "${NS}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "${POD}" ] && break
  sleep 5
done
log "C11: pod=${POD}"

deadline=$((SECONDS + 1800))
ph=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  ph="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${ph}" in Succeeded|Failed) break ;; esac
  sleep 15
done
log "C11: pod phase=${ph}"
log "C11: ===== container logs ====="
npu_kc -n "${NS}" logs "${POD}" --tail=200 || true
log "C11: ===== end logs ====="
[ "${ph}" = "Succeeded" ]
