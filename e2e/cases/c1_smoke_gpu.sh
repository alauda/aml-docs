#!/usr/bin/env bash
# C1 — exercises the published torch2.6-cu126-amd64:v0.1.0 TrainingRuntime via the
# shared trainjob-smoke.yaml from the training-runtimes guide. Pure smoke: probes
# torch+CUDA visibility and does a small matmul (synthetic data is the matmul
# input — generated inline by the runtime image, no external data needed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
ASSETS="${E2E_ROOT}/../docs/en/training_guides/assets/training-runtimes"

if [ -n "${GPU_DH_MIRROR}" ]; then
  log "C1: applying torch2.6-cu126-amd64 TrainingRuntime to ns/${NS} (Docker Hub mirror=${GPU_DH_MIRROR})"
else
  log "C1: applying torch2.6-cu126-amd64 TrainingRuntime to ns/${NS}"
fi
set_metadata_namespace "${NS}" < "${ASSETS}/torch2.6-cu126-amd64-trainingruntime.yaml" \
  | mirror_dockerhub "${GPU_DH_MIRROR}" \
  | retry_apply gpu_kc

log "C1: submitting TrainJob from trainjob-smoke.yaml"
TJ_NAME=$(set_metadata_namespace "${NS}" < "${ASSETS}/trainjob-smoke.yaml" \
          | retry_create gpu_kc -o jsonpath='{.metadata.name}')
log "C1: trainjob=${TJ_NAME}"

cleanup() {
  gpu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

# Wait for jobset pod to appear, then stream logs and wait for terminal state.
log "C1: waiting for jobset pod..."
deadline=$((SECONDS + 600))
pod=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  pod="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}")"
  [ -n "${pod}" ] && break
  sleep 5
done
[ -z "${pod}" ] && { log "C1: no pod appeared"; exit 1; }
log "C1: pod=${pod}"

# Wait until container has run (pod terminates Succeeded or Failed) then dump logs.
log "C1: waiting for pod terminal state..."
gpu_kc -n "${NS}" wait --for=jsonpath='{.status.phase}' pod/"${pod}" --timeout=600s 2>&1 | tee /tmp/c1_wait || true
# wait --for above watches Ready by default — fall back to a poll on phase.
deadline=$((SECONDS + 900))
phase=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  phase="$(gpu_kc -n "${NS}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in
    Succeeded|Failed) break ;;
  esac
  sleep 5
done
log "C1: pod phase=${phase}"
log "C1: ===== container logs ====="
gpu_kc -n "${NS}" logs "${pod}" --tail=200 || true
log "C1: ===== end logs ====="
[ "${phase}" = "Succeeded" ]
