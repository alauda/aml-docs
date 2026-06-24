#!/usr/bin/env bash
# C7 — same smoke but on the NPU cluster against torch2.6-cann8.5-arm64:v0.1.0.
# The published runtime YAML requests HAMI vNPU (huawei.com/Ascend910B4 +
# Ascend910B4-memory + schedulerName: hami-scheduler). The dev NPU cluster from
# my_dev_env_new.md exposes the standard Huawei k8s-device-plugin
# (huawei.com/Ascend910, no HAMI), so we patch the runtime in-place before apply.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${NPU_NAMESPACE}"
ASSETS="${E2E_ROOT}/../docs/en/training_guides/assets/training-runtimes"

log "C7: applying torch2.6-cann8.5-arm64 TrainingRuntime to ns/${NS} (non-HAMI patch + docker.io → ${NPU_DH_MIRROR})"
sed -e "s/namespace: kubeflow-admin-cpaas-io/namespace: ${NS}/" \
    -e '/schedulerName: hami-scheduler/d' \
    -e 's@huawei.com/Ascend910B4: "1"@huawei.com/Ascend910: "1"@' \
    -e '/huawei.com\/Ascend910B4-memory:/d' \
    "${ASSETS}/torch2.6-cann8.5-arm64-trainingruntime.yaml" \
  | mirror_dockerhub "${NPU_DH_MIRROR}" \
  | retry_apply npu_kc

log "C7: submitting TrainJob from trainjob-smoke.yaml (runtimeRef=torch2.6-cann8.5-arm64)"
# Override CPU request to 200m — Alauda OS 2 runs at ~99% CPU when shared with the dev workloads
# in this cluster, but has 4 free NPUs. The smoke probe just runs a matmul, 200m is plenty.
TJ_NAME=$(sed -e "s/namespace: kubeflow-admin-cpaas-io/namespace: ${NS}/" \
              -e 's/name: torch2.6-cu126-amd64/name: torch2.6-cann8.5-arm64/' \
              "${ASSETS}/trainjob-smoke.yaml" \
          | yq '.spec.trainer.resourcesPerNode = {"requests":{"cpu":"50m","memory":"512Mi"},"limits":{"cpu":"500m","memory":"4Gi","huawei.com/Ascend910":"1"}}' \
          | retry_create npu_kc -o jsonpath='{.metadata.name}')
log "C7: trainjob=${TJ_NAME}"

cleanup() {
  npu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C7: waiting for jobset pod..."
deadline=$((SECONDS + 900))
pod=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  pod="$(trainjob_pod npu_kc "${NS}" "${TJ_NAME}")"
  [ -n "${pod}" ] && break
  sleep 5
done
[ -z "${pod}" ] && { log "C7: no pod appeared"; exit 1; }
log "C7: pod=${pod}"

log "C7: waiting for pod terminal state..."
deadline=$((SECONDS + 1200))
phase=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  phase="$(npu_kc -n "${NS}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in
    Succeeded|Failed) break ;;
  esac
  sleep 10
done
log "C7: pod phase=${phase}"
log "C7: ===== container logs ====="
npu_kc -n "${NS}" logs "${pod}" --tail=200 || true
log "C7: ===== end logs ====="
[ "${phase}" = "Succeeded" ]
