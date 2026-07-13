#!/usr/bin/env bash
# C15 — requests a *slice* of a GPU through Dynamic Resource Allocation (DRA) and
# runs a self-contained LoRA SFT on it with Kubeflow Trainer v2. Exercises the
# assets from the "GPU Slicing with Dynamic Resource Allocation (DRA)" guide:
#   dra/<slice>-resourceclaimtemplate.yaml  ->  dra/dra-sft-trainingruntime.yaml
#   ->  dra/dra-sft-trainjob.yaml
#
# Needs the NVIDIA DRA driver advertising devices (ResourceSlices) on the cluster.
# Self-skips (E2E_SKIP_RC) when DRA isn't enabled so run_all.sh stays green on
# clusters that only have the classic device plugin.
#
# Env:
#   GPU_NAMESPACE   (required) namespace for the run
#   DRA_SLICE_MODE  mig (default) | shared   MIG slice vs. time-sliced full GPU
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

require_env GPU_NAMESPACE "namespace for GPU e2e resources"
NS="${GPU_NAMESPACE}"
MODE="${DRA_SLICE_MODE:-mig}"
ASSETS="${E2E_ROOT}/../docs/en/training_guides/assets/dra"

case "${MODE}" in
  mig)    RCT_FILE="mig-slice-resourceclaimtemplate.yaml";    RCT_NAME="mig-1g-6gb";           DEVCLASS="mig.nvidia.com" ;;
  shared) RCT_FILE="shared-gpu-resourceclaimtemplate.yaml";   RCT_NAME="shared-gpu-timeslice"; DEVCLASS="gpu.nvidia.com" ;;
  *) log "C15: unknown DRA_SLICE_MODE=${MODE} (want mig|shared)"; exit "${E2E_SKIP_RC}" ;;
esac

# Gate: is the DRA driver actually advertising devices for this device class?
if ! gpu_kc get deviceclass "${DEVCLASS}" >/dev/null 2>&1; then
  log "C15: DeviceClass ${DEVCLASS} absent — NVIDIA DRA driver not installed; skipping"
  exit "${E2E_SKIP_RC}"
fi
slices="$(gpu_kc get resourceslices \
  -o jsonpath="{range .items[?(@.spec.driver=='gpu.nvidia.com')]}{.metadata.name}{'\n'}{end}" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${slices}" = "0" ]; then
  log "C15: no ResourceSlices from gpu.nvidia.com — DRA kubelet-plugin not advertising devices; skipping"
  log "C15: (label the GPU node 'nvidia-device-enable=pgpu-dra' and, for MIG, enable MIG mode — see the guide)"
  exit "${E2E_SKIP_RC}"
fi
log "C15: DRA active (${slices} ResourceSlice(s) from gpu.nvidia.com); mode=${MODE} deviceclass=${DEVCLASS}"

log "C15: applying ResourceClaimTemplate ${RCT_NAME} to ns/${NS}"
set_metadata_namespace "${NS}" < "${ASSETS}/${RCT_FILE}" | retry_apply gpu_kc

log "C15: applying TrainingRuntime dra-mig-sft to ns/${NS} (claim=${RCT_NAME})"
set_metadata_namespace "${NS}" < "${ASSETS}/dra-sft-trainingruntime.yaml" \
  | sed "s/resourceClaimTemplateName: mig-1g-6gb/resourceClaimTemplateName: ${RCT_NAME}/" \
  | mirror_dockerhub "${GPU_DH_MIRROR}" \
  | retry_apply gpu_kc

log "C15: submitting TrainJob from dra-sft-trainjob.yaml"
TJ_NAME=$(set_metadata_namespace "${NS}" < "${ASSETS}/dra-sft-trainjob.yaml" \
          | retry_create gpu_kc -o jsonpath='{.metadata.name}')
log "C15: trainjob=${TJ_NAME}"

cleanup() {
  gpu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C15: waiting for jobset pod..."
deadline=$((SECONDS + 600))
pod=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  pod="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}")"
  [ -n "${pod}" ] && break
  sleep 5
done
[ -z "${pod}" ] && { log "C15: no pod appeared"; exit 1; }
log "C15: pod=${pod}"

log "C15: waiting for pod terminal state..."
deadline=$((SECONDS + 900))
phase=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  phase="$(gpu_kc -n "${NS}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in
    Succeeded|Failed) break ;;
  esac
  sleep 5
done
log "C15: pod phase=${phase}"
log "C15: ===== container logs ====="
logs="$(gpu_kc -n "${NS}" logs "${pod}" --tail=200 2>&1 || true)"
printf '%s\n' "${logs}"
log "C15: ===== end logs ====="

[ "${phase}" = "Succeeded" ] && printf '%s\n' "${logs}" | grep -q "DRA LoRA SFT on GPU slice: OK"
