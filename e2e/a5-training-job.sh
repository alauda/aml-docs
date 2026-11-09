#!/usr/bin/env bash
# Shared Job lifecycle for the C19 and C18 A5 workloads.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"
require_env NPU_NAMESPACE "namespace for A5 training Jobs"
require_env A5_IMAGE
require_env A5_CASE
A5_TIMEOUT="${A5_TIMEOUT:-1800}"
case "${A5_TIMEOUT}" in ''|*[!0-9]*|0*) log 'A5_TIMEOUT must be a positive number of seconds'; exit 2;; esac
if [ -n "${E2E_NPU_NODE_SELECTOR_KEY:-}" ] && [ -z "${E2E_NPU_NODE_SELECTOR_VALUE:-}" ]; then
  log 'E2E_NPU_NODE_SELECTOR_KEY requires E2E_NPU_NODE_SELECTOR_VALUE'; exit 2
fi
JOB="a5-$(echo "${A5_CASE}" | tr '[:upper:]' '[:lower:]')-$(date -u +%s)-$$"
EVIDENCE="${A5_OUTPUT_DIR:-${LOG_DIR}}/${JOB}"
mkdir -p "${EVIDENCE}"
created=0
a5_kc() { npu_kc --request-timeout=30s "$@"; }
finish() {
  local rc=$?
  trap - EXIT
  if [ "${created}" = 1 ]; then
    a5_kc -n "${NPU_NAMESPACE}" get job "${JOB}" -o json >"${EVIDENCE}/job.json" 2>&1 || true
    a5_kc -n "${NPU_NAMESPACE}" get pods -l "job-name=${JOB}" -o json >"${EVIDENCE}/pods.json" 2>&1 || true
    a5_kc -n "${NPU_NAMESPACE}" describe job "${JOB}" >"${EVIDENCE}/describe.txt" 2>&1 || true
    a5_kc -n "${NPU_NAMESPACE}" logs "job/${JOB}" --pod-running-timeout=10s --all-containers=true >"${EVIDENCE}/train.log" 2>&1 || true
    cat "${EVIDENCE}/train.log"
    if [ "${A5_KEEP_RESOURCES:-0}" != 1 ]; then
      a5_kc -n "${NPU_NAMESPACE}" delete job "${JOB}" --ignore-not-found --wait=false || true
    fi
  fi
  log "${A5_CASE}: exit=${rc}; evidence=${EVIDENCE}"
  exit "${rc}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export A5_CASE A5_IMAGE A5_TIMEOUT NPU_NAMESPACE
export A5_JOB_NAME="${JOB}" A5_ASSETS="${HERE}/assets/a5-training"
python3 - <<'PY' >"${EVIDENCE}/job.yaml"
import json, os
from pathlib import Path

e = os.environ
case = e['A5_CASE']
assets = Path(e['A5_ASSETS'])
if case == 'C19':
    payload = (assets / 'c19_lora.sh').read_text()
    count = '1'
else:
    payload = '''set -eo pipefail
for f in /usr/local/Ascend/cann/set_env.sh /usr/local/Ascend/ascend-toolkit/set_env.sh /usr/local/Ascend/nnal/atb/set_env.sh; do
  [ ! -f "$f" ] || source "$f"
done
set -u
cat > /tmp/c18_train.py <<'PYTHON'
''' + (assets / 'c18_train.py').read_text() + '''PYTHON
export C18_NPU_COUNT=2
torchrun --standalone --nnodes=1 --nproc-per-node=2 /tmp/c18_train.py
'''
    count = '2'
container = {
    'name': 'trainer', 'image': e['A5_IMAGE'], 'imagePullPolicy': 'IfNotPresent',
    'command': ['/bin/bash', '-lc'], 'args': [payload],
    'env': [{'name': 'HCCL_CONNECT_TIMEOUT', 'value': '120'}],
    'resources': {
        'requests': {'cpu': '2', 'memory': '8Gi', 'huawei.com/npu': count},
        'limits': {'cpu': '8', 'memory': '16Gi', 'huawei.com/npu': count}},
    'volumeMounts': [{'name': 'workspace', 'mountPath': '/workspace'},
                     {'name': 'dshm', 'mountPath': '/dev/shm'}]}
pod = {'restartPolicy': 'Never', 'containers': [container], 'volumes': [
    {'name': 'workspace', 'emptyDir': {}},
    {'name': 'dshm', 'emptyDir': {'medium': 'Memory', 'sizeLimit': '2Gi'}}]}
if case == 'C18':
    pod['securityContext'] = {'runAsNonRoot': True, 'runAsUser': 1001, 'runAsGroup': 0, 'fsGroup': 1000}
    container['securityContext'] = {'allowPrivilegeEscalation': False,
        'capabilities': {'drop': ['ALL']}, 'seccompProfile': {'type': 'RuntimeDefault'}}
secret = e.get('E2E_IMAGE_PULL_SECRET')
if secret:
    pod['imagePullSecrets'] = [{'name': secret}]
if e.get('NPU_RUNTIME_CLASS'):
    pod['runtimeClassName'] = e['NPU_RUNTIME_CLASS']
if e.get('E2E_NPU_NODE_SELECTOR_KEY'):
    pod['nodeSelector'] = {e['E2E_NPU_NODE_SELECTOR_KEY']: e['E2E_NPU_NODE_SELECTOR_VALUE']}
job = {'apiVersion': 'batch/v1', 'kind': 'Job',
    'metadata': {'name': e['A5_JOB_NAME'], 'namespace': e['NPU_NAMESPACE']},
    'spec': {'completions': 1, 'parallelism': 1, 'backoffLimit': 0, 'activeDeadlineSeconds': int(e['A5_TIMEOUT']),
             'template': {'spec': pod}}}
print(json.dumps(job, indent=2))
PY
log "${A5_CASE}: submitting ${JOB} (image=${A5_IMAGE})"
a5_kc create -f "${EVIDENCE}/job.yaml"
created=1
deadline=$((SECONDS + A5_TIMEOUT + 30))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  state="$(a5_kc -n "${NPU_NAMESPACE}" get job "${JOB}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}:{.status.conditions[?(@.type=="Failed")].status}')"
  case "${state}" in
    True:*)
      a5_kc -n "${NPU_NAMESPACE}" logs "job/${JOB}" --pod-running-timeout=10s --all-containers=true >"${EVIDENCE}/train.log"
      if [ "${A5_CASE}" = C19 ]; then
        grep -Fq 'PASS: C19 completed 2 LoRA steps with finite loss and adapter weights' "${EVIDENCE}/train.log"
      else
        grep -Fq 'PASS: 2 NPU ranks completed DDP optimizer step and HCCL all_reduce=3.0' "${EVIDENCE}/train.log"
      fi
      exit 0 ;;
    *:True) log "${A5_CASE}: Job failed"; exit 1 ;;
  esac
  sleep 5
done
log "${A5_CASE}: Job timed out"
exit 1
