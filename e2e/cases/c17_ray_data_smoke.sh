#!/usr/bin/env bash
# C17 — CPU Ray Data actor-pool smoke from run-ray-data-pipelines.mdx.
# Submits assets/ray-data-pipelines/rayjob-smoke.yaml: from_items + map_batches
# with ActorPoolStrategy. No Docling, no PDF PVC, no S3.
#
# Env:
#   RAY_DATA_NAMESPACE  (required; falls back to GPU_NAMESPACE)
#   RAY_DATA_IMAGE      cluster-pullable Ray image (default: the x86
#                       build-harbor ray-mlflow-training image already used
#                       by the KubeRay MLflow guide)
#   RAY_DATA_CONTEXT / RAY_DATA_KUBECONFIG  optional; default GPU_* then current
#   RAY_DATA_KEEP_RESOURCES=1  leave the RayJob after the run
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env RAY_DATA_NAMESPACE "namespace for Ray Data e2e resources"
NS="${RAY_DATA_NAMESPACE}"
ASSETS="${E2E_ROOT}/../docs/en/train/guides/assets/ray-data-pipelines"
IMAGE="${RAY_DATA_IMAGE:-build-harbor.alauda.cn/mlops/ray-mlflow-training:pr317-test-20260826-ready}"

ray_data_kc get crd rayjobs.ray.io >/dev/null 2>&1 || {
  log "C17: RayJob CRD missing; skipping"
  exit "${E2E_SKIP_RC}"
}

test -f "${ASSETS}/rayjob-smoke.yaml"

PULL_SECRET="${E2E_IMAGE_PULL_SECRET:-}"
if [ -z "${PULL_SECRET}" ] && ray_data_kc -n "${NS}" get secret harbor-pull >/dev/null 2>&1; then
  PULL_SECRET="harbor-pull"
fi

log "C17: submitting RayJob smoke in ns/${NS} image=${IMAGE} pullSecret=${PULL_SECRET:-none}"
manifest="$(sed "s#image: <image>#image: ${IMAGE}#" "${ASSETS}/rayjob-smoke.yaml")"
if [ -n "${PULL_SECRET}" ]; then
  manifest="$(printf '%s\n' "${manifest}" | sed "s#imagePullSecrets: \[\]#imagePullSecrets:\n            - name: ${PULL_SECRET}#")"
else
  manifest="$(printf '%s\n' "${manifest}" | sed '/imagePullSecrets: \[\]/d')"
fi
JOB="$(printf '%s\n' "${manifest}" | retry_create ray_data_kc -n "${NS}" -o jsonpath='{.metadata.name}')"
log "C17: rayjob=${JOB}"

cleanup() {
  if [ "${RAY_DATA_KEEP_RESOURCES}" != 1 ]; then
    ray_data_kc -n "${NS}" delete rayjob "${JOB}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

deadline=$((SECONDS + 600))
status=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  status="$(ray_data_kc -n "${NS}" get rayjob "${JOB}" -o jsonpath='{.status.jobStatus}' 2>/dev/null || true)"
  case "${status}" in
    SUCCEEDED|FAILED|STOPPED) break ;;
  esac
  sleep 10
done

[ "${status}" = "SUCCEEDED" ] || {
  log "C17: jobStatus=${status:-empty} (want SUCCEEDED)"
  ray_data_kc -n "${NS}" get rayjob "${JOB}" -o yaml || true
  exit 1
}

# KubeRay K8sJobMode runs the entrypoint in a submitter Job named after the RayJob.
logs="$(ray_data_kc -n "${NS}" logs "job/${JOB}" 2>/dev/null || true)"
if [ -z "${logs}" ]; then
  cluster="$(ray_data_kc -n "${NS}" get rayjob "${JOB}" -o jsonpath='{.status.rayClusterName}' 2>/dev/null || true)"
  pod="$(ray_data_kc -n "${NS}" get pods -l "ray.io/cluster=${cluster},ray.io/node-type=head" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  logs="$(ray_data_kc -n "${NS}" logs "${pod}" -c ray-head 2>/dev/null || true)"
fi
printf '%s\n' "${logs}" | tail -n 40
echo "${logs}" | grep -q "RAY_DATA_SMOKE_OK" || {
  log "C17: RayJob succeeded but RAY_DATA_SMOKE_OK missing from submitter logs"
  exit 1
}
log "C17: PASS"
