#!/usr/bin/env bash
# C18 — two-process NPU training smoke with both workers inside one pod.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env NPU_NAMESPACE "namespace for NPU e2e resources"
require_env NPU_RESOURCE_NAME "extended resource name for NPUs, for example huawei.com/npu"
NS="${NPU_NAMESPACE}"
JOB="c18-multi-npu-$(date -u +%Y%m%d%H%M%S)"
IMAGE="${C18_IMAGE:-docker.io/alaudadockerhub/torch2.6-cann8.5-arm64:v0.1.0}"
NPUS="${C18_NPU_COUNT:-2}"
IMAGE_PULL_SECRET="${C18_IMAGE_PULL_SECRET:-${E2E_IMAGE_PULL_SECRET:-}}"
RUNTIME_CLASS="${NPU_RUNTIME_CLASS:-}"

case "${NPUS}" in
  ''|*[!0-9]*) log "C18_NPU_COUNT must be a positive integer"; exit 2 ;;
esac
[ "${NPUS}" -ge 2 ] || { log "C18_NPU_COUNT must be at least 2"; exit 2; }

log "C18: submitting Job ${JOB} (image=${IMAGE}, ${NPU_RESOURCE_NAME}=${NPUS})"
cat <<YAML | mirror_dockerhub "${NPU_DH_MIRROR}" | retry_create npu_kc
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
  namespace: ${NS}
  labels:
    alauda.io/e2e-case: c18-multi-npu-single-pod
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 1800
  template:
    metadata:
      labels:
        alauda.io/e2e-case: c18-multi-npu-single-pod
    spec:
      restartPolicy: Never
$(yaml_scalar_field 6 runtimeClassName "${RUNTIME_CLASS}")
$(yaml_image_pull_secrets 6 "${IMAGE_PULL_SECRET}")
$(yaml_node_selector 6 "${E2E_NPU_NODE_SELECTOR_KEY:-}" "${E2E_NPU_NODE_SELECTOR_VALUE:-}")
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 0
        fsGroup: 1000
      volumes:
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 2Gi
      containers:
        - name: trainer
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["bash", "-lc"]
          args:
            - |
              set -eo pipefail
              for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
                [ ! -f "\$f" ] || source "\$f"
              done
              set -u
              cat > /tmp/c18_train.py <<'PY'
              import os
              import torch
              import torch.distributed as dist
              import torch.nn as nn
              import torch_npu

              local_rank = int(os.environ["LOCAL_RANK"])
              assert torch.npu.device_count() >= int(os.environ["C18_NPU_COUNT"]), (
                  f"expected {os.environ['C18_NPU_COUNT']} visible NPUs, got {torch.npu.device_count()}"
              )
              torch.npu.set_device(local_rank)
              device = torch.device("npu", local_rank)
              dist.init_process_group(backend="hccl")
              print(f"rank={dist.get_rank()} local_rank={local_rank} device={device} world_size={dist.get_world_size()}", flush=True)
              assert dist.get_world_size() == int(os.environ["C18_NPU_COUNT"])

              model = nn.parallel.DistributedDataParallel(
                  nn.Linear(16, 4, bias=False).to(device),
                  device_ids=[local_rank],
                  output_device=local_rank,
              )
              optimizer = torch.optim.SGD(model.parameters(), lr=0.01)
              x = torch.full((8, 16), float(dist.get_rank() + 1), device=device)
              loss = model(x).square().mean()
              optimizer.zero_grad()
              loss.backward()
              optimizer.step()

              result = torch.tensor([float(dist.get_rank() + 1)], device=device)
              dist.all_reduce(result, op=dist.ReduceOp.SUM)
              assert result.item() == dist.get_world_size() * (dist.get_world_size() + 1) / 2
              dist.barrier()
              if dist.get_rank() == 0:
                  print(f"PASS: {dist.get_world_size()} NPU ranks completed DDP optimizer step and HCCL all_reduce={result.item()}", flush=True)
              dist.destroy_process_group()
              PY
              export C18_NPU_COUNT=${NPUS}
              torchrun --standalone --nnodes=1 --nproc-per-node=${NPUS} /tmp/c18_train.py
          env:
            - name: HCCL_CONNECT_TIMEOUT
              value: "120"
          resources:
            requests:
              cpu: "2"
              memory: 4Gi
            limits:
              cpu: "8"
              memory: 16Gi
              ${NPU_RESOURCE_NAME}: "${NPUS}"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          volumeMounts:
            - name: dshm
              mountPath: /dev/shm
YAML

cleanup() {
  npu_kc -n "${NS}" delete job "${JOB}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "C18: waiting for Job completion..."
deadline=$((SECONDS + 1800))
condition=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  condition="$(npu_kc -n "${NS}" get job "${JOB}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}:{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)"
  case "${condition}" in
    True:) break ;;
    :True) break ;;
  esac
  sleep 10
done
if [ "${condition}" != "True:" ]; then
  log "C18: Job failed or timed out (condition=${condition}); collecting pod state and logs"
  npu_kc -n "${NS}" get pods -l "job-name=${JOB}" -o wide || true
  npu_kc -n "${NS}" logs "job/${JOB}" --all-containers=true --tail=300 || true
  npu_kc -n "${NS}" describe job "${JOB}" || true
  exit 1
fi
log "C18: Job completed; logs:"
POD="$(npu_kc -n "${NS}" get pods -l "job-name=${JOB}" -o jsonpath='{.items[0].metadata.name}')"
[ -n "${POD}" ] || { log "C18: Job completed but its pod could not be found"; exit 1; }
DEVICES="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.metadata.annotations.huawei\.com/AscendReal}')"
ALLOCATED="$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.spec.containers[0].resources.limits.huawei\.com/npu}')"
log "C18: pod=${POD} node=$(npu_kc -n "${NS}" get pod "${POD}" -o jsonpath='{.spec.nodeName}') requested huawei.com/npu=${ALLOCATED} physical devices=${DEVICES}"
npu_kc -n "${NS}" logs "${POD}" --all-containers=true --tail=300
