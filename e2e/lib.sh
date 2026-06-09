#!/usr/bin/env bash
# Shared helpers for the training-guides e2e harness.
# Sourced by run_all.sh and every case script.

set -uo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${E2E_ROOT}/logs"
mkdir -p "${LOG_DIR}"

GPU_CONTEXT="${GPU_CONTEXT:-g1-c1-x86-admin@g1-c1-x86}"
GPU_NAMESPACE="${GPU_NAMESPACE:-mlops-demo-e2e}"
NPU_KUBECONFIG="${NPU_KUBECONFIG:-${HOME:-/tmp}/.kube/npu-env.yaml}"
NPU_NAMESPACE="${NPU_NAMESPACE:-mlops-demo-ai-test}"
# Docker Hub mirror prefixes — both clusters firewall registry-1.docker.io.
# GPU cluster: docker-mirrors.alauda.cn proxies docker.io.
# NPU cluster: docker.1ms.run proxies docker.io (per my_dev_env_new.md).
GPU_DH_MIRROR="${GPU_DH_MIRROR:-docker-mirrors.alauda.cn}"
NPU_DH_MIRROR="${NPU_DH_MIRROR:-docker.1ms.run}"

# Rewrite docker.io references to a mirror that the cluster can actually reach.
# Args: mirror_host. Reads stdin, writes patched YAML to stdout.
mirror_dockerhub() {
  local m="$1"
  sed -e "s@docker.io/@${m}/@g" -e "s@image: alaudadockerhub/@image: ${m}/alaudadockerhub/@g"
}

gpu_kc() { kubectl --context "${GPU_CONTEXT}" "$@"; }
npu_kc() { KUBECONFIG="${NPU_KUBECONFIG}" kubectl "$@"; }

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# Reap a background log-follower without blocking. Used after a polling loop
# that walks a pod to a terminal phase — if the pod never gets there, the
# `kubectl logs -f` stays alive forever; without this `wait` would inherit
# its hang.
reap_logs() {
  local pid="${1:-}"
  [ -z "${pid}" ] && return 0
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}

# Wait until kubectl JSONPath produces a value from a known set.
# Args: kctl_fn kind name ns jsonpath success_values... timeout_seconds
wait_for_status() {
  local kfn="$1" kind="$2" name="$3" ns="$4" path="$5"
  shift 5
  local timeout="${!#}"
  local n=$(( $# - 1 ))
  local expected=( "${@:1:$n}" )
  local deadline=$(( SECONDS + timeout ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local got
    got="$($kfn get "${kind}" "${name}" -n "${ns}" -o jsonpath="${path}" 2>/dev/null || true)"
    for e in "${expected[@]}"; do
      if [ "${got}" = "${e}" ]; then
        echo "${got}"
        return 0
      fi
    done
    sleep 5
  done
  echo "timeout waiting for ${kind}/${name} ${path} to be one of ${expected[*]}; last=${got}" >&2
  return 1
}

# Run a kubectl verb (create / apply) reading YAML from stdin, retrying on
# transient webhook TLS failures from the kubeflow-trainer cert-rotator.
# Args: kctl_fn verb [extra-kubectl-args ...]
# Echoes stdout from the successful call.
_retry_kubectl_stdin() {
  local kfn="$1" verb="$2"; shift 2
  local data
  data="$(cat)"
  local attempts=0 max=20 delay=30 rc out
  while [ "${attempts}" -lt "${max}" ]; do
    if out="$(printf '%s' "${data}" | $kfn "${verb}" -f - "$@" 2>&1)"; then
      printf '%s' "${out}"
      return 0
    fi
    rc=$?
    if ! echo "${out}" | grep -qE 'failed calling webhook|x509|connection refused|EOF|context deadline exceeded|webhook.* connect: connection refused'; then
      printf '%s\n' "${out}" >&2
      return "${rc}"
    fi
    attempts=$((attempts+1))
    log "kubectl ${verb}: webhook flake (attempt ${attempts}/${max}), sleeping ${delay}s"
    sleep "${delay}"
  done
  printf '%s\n' "${out}" >&2
  return 1
}

retry_create() { _retry_kubectl_stdin "$1" create "${@:2}"; }
retry_apply()  { _retry_kubectl_stdin "$1" apply  "${@:2}"; }

# Locate a TrainJob's pod. Trainer v2 builds a JobSet named after the TrainJob,
# with one Job per `replicatedJobs[*]` named `${trainjob}-<rjob>-0`. The first
# pod under it is what we stream logs from. `rjob` defaults to `node` (the
# convention used by the published runtimes).
trainjob_pod() {
  local kfn="$1" ns="$2" trainjob="$3" rjob="${4:-node}"
  # kubectl's -l only keeps the last flag; AND'd selectors must be comma-separated.
  $kfn -n "${ns}" get pods \
    -l "jobset.sigs.k8s.io/jobset-name=${trainjob},jobset.sigs.k8s.io/replicatedjob-name=${rjob}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}
