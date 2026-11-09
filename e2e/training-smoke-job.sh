#!/usr/bin/env bash
# Shared Job lifecycle for the C19 and C18 training workloads.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"
TRAINING_DEVICE="${TRAINING_DEVICE:-gpu}"
case "${TRAINING_DEVICE}" in
  gpu)
    TRAINING_NAMESPACE="${TRAINING_NAMESPACE:-${GPU_NAMESPACE}}"
    TRAINING_CONTEXT="${TRAINING_CONTEXT:-${GPU_CONTEXT}}"
    TRAINING_KUBECONFIG="${TRAINING_KUBECONFIG:-${GPU_KUBECONFIG}}"
    TRAINING_RESOURCE_NAME="${TRAINING_RESOURCE_NAME:-nvidia.com/gpu}"
    TRAINING_NODE_SELECTOR_KEY="${TRAINING_NODE_SELECTOR_KEY:-${E2E_GPU_NODE_SELECTOR_KEY:-}}"
    TRAINING_NODE_SELECTOR_VALUE="${TRAINING_NODE_SELECTOR_VALUE:-${E2E_GPU_NODE_SELECTOR_VALUE:-}}"
    ;;
  npu)
    TRAINING_NAMESPACE="${TRAINING_NAMESPACE:-${NPU_NAMESPACE}}"
    TRAINING_CONTEXT="${TRAINING_CONTEXT:-${NPU_CONTEXT}}"
    TRAINING_KUBECONFIG="${TRAINING_KUBECONFIG:-${NPU_KUBECONFIG}}"
    TRAINING_RESOURCE_NAME="${TRAINING_RESOURCE_NAME:-huawei.com/npu}"
    TRAINING_RUNTIME_CLASS="${TRAINING_RUNTIME_CLASS:-${NPU_RUNTIME_CLASS:-}}"
    TRAINING_NODE_SELECTOR_KEY="${TRAINING_NODE_SELECTOR_KEY:-${E2E_NPU_NODE_SELECTOR_KEY:-}}"
    TRAINING_NODE_SELECTOR_VALUE="${TRAINING_NODE_SELECTOR_VALUE:-${E2E_NPU_NODE_SELECTOR_VALUE:-}}"
    ;;
  cpu)
    TRAINING_NAMESPACE="${TRAINING_NAMESPACE:-}"
    TRAINING_CONTEXT="${TRAINING_CONTEXT:-}"
    TRAINING_KUBECONFIG="${TRAINING_KUBECONFIG:-}"
    TRAINING_RESOURCE_NAME=""
    ;;
  *) log 'TRAINING_DEVICE must be gpu, npu, or cpu'; exit 2 ;;
esac
require_env TRAINING_NAMESPACE "namespace for training Jobs (or set GPU_NAMESPACE/NPU_NAMESPACE)"
require_env TRAINING_CASE
if [ -z "${TRAINING_IMAGE:-}" ] && [ "${TRAINING_DEVICE}" != npu ]; then
  if [ "${TRAINING_CASE}" = C19 ]; then
    TRAINING_IMAGE=docker.io/alaudadockerhub/llamafactory0.9-cu126-amd64:v0.1.0
  else
    TRAINING_IMAGE=docker.io/alaudadockerhub/torch2.6-cu126-amd64:v0.1.0
  fi
fi
require_env TRAINING_IMAGE "set C18_IMAGE/C19_IMAGE for a device-compatible image"
TRAINING_TIMEOUT="${TRAINING_TIMEOUT:-1800}"
case "${TRAINING_TIMEOUT}" in ''|*[!0-9]*|0*) log 'TRAINING_TIMEOUT must be a positive number of seconds'; exit 2;; esac
if [ -n "${TRAINING_NODE_SELECTOR_KEY:-}" ] && [ -z "${TRAINING_NODE_SELECTOR_VALUE:-}" ]; then
  log 'TRAINING_NODE_SELECTOR_KEY requires TRAINING_NODE_SELECTOR_VALUE'; exit 2
fi
JOB="train-$(echo "${TRAINING_CASE}" | tr '[:upper:]' '[:lower:]')-$(date -u +%s)-$$"
EVIDENCE="${TRAINING_OUTPUT_DIR:-${LOG_DIR}}/${JOB}"
mkdir -p "${EVIDENCE}"
created=0
training_kc() { _kubectl_with_env "${TRAINING_KUBECONFIG}" "${TRAINING_CONTEXT}" --request-timeout=30s "$@"; }
finish() {
  local rc=$?
  trap - EXIT
  if [ "${created}" = 1 ]; then
    training_kc -n "${TRAINING_NAMESPACE}" get job "${JOB}" -o json >"${EVIDENCE}/job.json" 2>&1 || true
    training_kc -n "${TRAINING_NAMESPACE}" get pods -l "job-name=${JOB}" -o json >"${EVIDENCE}/pods.json" 2>&1 || true
    training_kc -n "${TRAINING_NAMESPACE}" describe job "${JOB}" >"${EVIDENCE}/describe.txt" 2>&1 || true
    training_kc -n "${TRAINING_NAMESPACE}" logs "job/${JOB}" --pod-running-timeout=10s --all-containers=true >"${EVIDENCE}/train.log" 2>&1 || true
    cat "${EVIDENCE}/train.log"
    if [ "${TRAINING_KEEP_RESOURCES:-0}" != 1 ]; then
      training_kc -n "${TRAINING_NAMESPACE}" delete job "${JOB}" --ignore-not-found --wait=false || true
    fi
  fi
  log "${TRAINING_CASE}: exit=${rc}; evidence=${EVIDENCE}"
  exit "${rc}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export TRAINING_CASE TRAINING_IMAGE TRAINING_TIMEOUT TRAINING_NAMESPACE TRAINING_DEVICE TRAINING_RESOURCE_NAME
export TRAINING_NODE_SELECTOR_KEY="${TRAINING_NODE_SELECTOR_KEY:-}" TRAINING_NODE_SELECTOR_VALUE="${TRAINING_NODE_SELECTOR_VALUE:-}"
export TRAINING_RUNTIME_CLASS="${TRAINING_RUNTIME_CLASS:-}"
export TRAINING_JOB_NAME="${JOB}" TRAINING_ASSETS="${HERE}/assets/training-smoke"
python3 - <<'PY' >"${EVIDENCE}/job.yaml"
import json, os
from pathlib import Path

e = os.environ
case = e['TRAINING_CASE']
assets = Path(e['TRAINING_ASSETS'])
if case == 'C19':
    payload = (assets / 'c19_lora.sh').read_text()
    count = '1'
else:
    payload = '''set -eo pipefail
if [ "$TRAINING_DEVICE" = npu ]; then
  for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
    [ ! -f "$f" ] || source "$f"
  done
fi
set -u
cat > /tmp/c18_train.py <<'PYTHON'
''' + (assets / 'c18_train.py').read_text() + '''PYTHON
export TRAINING_PROCESS_COUNT=2
torchrun --standalone --nnodes=1 --nproc-per-node=2 /tmp/c18_train.py
'''
    count = '2'
image = e['TRAINING_IMAGE']
mirror = e.get('NPU_DH_MIRROR' if e['TRAINING_DEVICE'] == 'npu' else 'GPU_DH_MIRROR', '')
if mirror and image.startswith('docker.io/'):
    image = mirror.rstrip('/') + '/' + image.removeprefix('docker.io/')
container = {
    'name': 'trainer', 'image': image, 'imagePullPolicy': 'IfNotPresent',
    'command': ['/bin/bash', '-lc'], 'args': [payload],
    'env': [{'name': 'TRAINING_DEVICE', 'value': e['TRAINING_DEVICE']},
            {'name': 'TRAINING_PIP_INDEX_URL', 'value': e.get('TRAINING_PIP_INDEX_URL', 'https://pypi.org/simple')}],
    'resources': {
        'requests': {'cpu': '2', 'memory': '8Gi'},
        'limits': {'cpu': '8', 'memory': '16Gi'}},
    'volumeMounts': [{'name': 'workspace', 'mountPath': '/workspace'},
                     {'name': 'dshm', 'mountPath': '/dev/shm'}]}
if e['TRAINING_DEVICE'] == 'npu':
    container['env'].append({'name': 'HCCL_CONNECT_TIMEOUT', 'value': '120'})
if e['TRAINING_RESOURCE_NAME']:
    for key in ('requests', 'limits'):
        container['resources'][key][e['TRAINING_RESOURCE_NAME']] = count
pod = {'restartPolicy': 'Never', 'securityContext': {'fsGroup': 1000},
       'containers': [container], 'volumes': [
    {'name': 'workspace', 'emptyDir': {}},
    {'name': 'dshm', 'emptyDir': {'medium': 'Memory', 'sizeLimit': '2Gi'}}]}
if case == 'C18':
    container['env'].append({'name': 'HOME', 'value': '/tmp'})
    pod['securityContext'] = {'runAsNonRoot': True, 'runAsUser': 1001, 'runAsGroup': 0, 'fsGroup': 1000}
    container['securityContext'] = {'allowPrivilegeEscalation': False,
        'capabilities': {'drop': ['ALL']}, 'seccompProfile': {'type': 'RuntimeDefault'}}
secret = e.get('E2E_IMAGE_PULL_SECRET')
if secret:
    pod['imagePullSecrets'] = [{'name': secret}]
if e.get('TRAINING_RUNTIME_CLASS'):
    pod['runtimeClassName'] = e['TRAINING_RUNTIME_CLASS']
if e.get('TRAINING_NODE_SELECTOR_KEY'):
    pod['nodeSelector'] = {e['TRAINING_NODE_SELECTOR_KEY']: e['TRAINING_NODE_SELECTOR_VALUE']}
job = {'apiVersion': 'batch/v1', 'kind': 'Job',
    'metadata': {'name': e['TRAINING_JOB_NAME'], 'namespace': e['TRAINING_NAMESPACE']},
    'spec': {'completions': 1, 'parallelism': 1, 'backoffLimit': 0, 'activeDeadlineSeconds': int(e['TRAINING_TIMEOUT']),
             'template': {'spec': pod}}}
print(json.dumps(job, indent=2))
PY
log "${TRAINING_CASE}: submitting ${JOB} (image=${TRAINING_IMAGE})"
training_kc create -f "${EVIDENCE}/job.yaml"
created=1
deadline=$((SECONDS + TRAINING_TIMEOUT + 30))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  state="$(training_kc -n "${TRAINING_NAMESPACE}" get job "${JOB}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}:{.status.conditions[?(@.type=="Failed")].status}')"
  case "${state}" in
    True:*)
      training_kc -n "${TRAINING_NAMESPACE}" logs "job/${JOB}" --pod-running-timeout=10s --all-containers=true >"${EVIDENCE}/train.log"
      if [ "${TRAINING_CASE}" = C19 ]; then
        grep -Fq 'PASS: C19 completed 2 LoRA steps with finite loss and adapter weights' "${EVIDENCE}/train.log"
      else
        grep -Fq 'PASS: C18 completed 2 ranks, DDP optimizer step and all_reduce=3.0' "${EVIDENCE}/train.log"
      fi
      exit 0 ;;
    *:True) log "${TRAINING_CASE}: Job failed"; exit 1 ;;
  esac
  sleep 5
done
log "${TRAINING_CASE}: Job timed out"
exit 1
