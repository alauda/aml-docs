#!/usr/bin/env bash
# Shared helpers for the training-guides e2e harness.
# Sourced by run_all.sh and every case script.

set -uo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${E2E_ROOT}/logs"
mkdir -p "${LOG_DIR}"

E2E_SKIP_RC="${E2E_SKIP_RC:-77}"
# Must be a valid process exit status (0–255), otherwise `exit "${E2E_SKIP_RC}"`
# gets truncated mod 256 while run_all.sh still compares against the raw value —
# skips would then be misreported as FAIL. Reject non-numeric / out-of-range
# overrides back to the default.
case "${E2E_SKIP_RC}" in
  *[!0-9]*) E2E_SKIP_RC=77 ;;
  *) [ "${E2E_SKIP_RC}" -ge 0 ] && [ "${E2E_SKIP_RC}" -le 255 ] || E2E_SKIP_RC=77 ;;
esac

# Required per case: GPU_NAMESPACE or NPU_NAMESPACE.
# Optional kube target: GPU_CONTEXT/GPU_KUBECONFIG/NPU_CONTEXT/NPU_KUBECONFIG.
# Optional Docker Hub mirrors: GPU_DH_MIRROR/NPU_DH_MIRROR.
# Optional private registry access: E2E_IMAGE_PULL_SECRET.
# Optional scheduling/storage: E2E_GPU_NODE_SELECTOR_KEY/VALUE, E2E_RWX_STORAGE_CLASS.
GPU_CONTEXT="${GPU_CONTEXT:-}"
GPU_KUBECONFIG="${GPU_KUBECONFIG:-}"
GPU_NAMESPACE="${GPU_NAMESPACE:-}"
NPU_CONTEXT="${NPU_CONTEXT:-}"
NPU_KUBECONFIG="${NPU_KUBECONFIG:-}"
NPU_NAMESPACE="${NPU_NAMESPACE:-}"
GPU_DH_MIRROR="${GPU_DH_MIRROR:-}"
NPU_DH_MIRROR="${NPU_DH_MIRROR:-}"

# Rewrite docker.io references to a mirror that the cluster can actually reach.
# Args: mirror_host. Reads stdin, writes patched YAML to stdout.
mirror_dockerhub() {
  local m="$1"
  if [ -z "${m}" ]; then
    cat
    return 0
  fi
  sed -e "s@docker.io/@${m}/@g" -e "s@image: alaudadockerhub/@image: ${m}/alaudadockerhub/@g"
}

set_metadata_namespace() {
  local ns="$1"
  awk -v ns="${ns}" '
    /^  namespace: / && !done { print "  namespace: " ns; done=1; next }
    { print }
  '
}

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

require_env() {
  local name="$1" hint="${2:-}"
  if [ -z "${!name:-}" ]; then
    if [ -n "${hint}" ]; then
      log "missing required env ${name}: ${hint}"
    else
      log "missing required env ${name}"
    fi
    exit "${E2E_SKIP_RC}"
  fi
}

_kubectl_with_env() {
  local kubeconfig="$1" context="$2"
  shift 2
  if [ -n "${kubeconfig}" ] && [ -n "${context}" ]; then
    KUBECONFIG="${kubeconfig}" kubectl --context "${context}" "$@"
  elif [ -n "${kubeconfig}" ]; then
    KUBECONFIG="${kubeconfig}" kubectl "$@"
  elif [ -n "${context}" ]; then
    kubectl --context "${context}" "$@"
  else
    kubectl "$@"
  fi
}

gpu_kc() { _kubectl_with_env "${GPU_KUBECONFIG}" "${GPU_CONTEXT}" "$@"; }
npu_kc() { _kubectl_with_env "${NPU_KUBECONFIG}" "${NPU_CONTEXT}" "$@"; }

yaml_scalar_field() {
  local indent="$1" name="$2" value="${3:-}"
  [ -z "${value}" ] && return 0
  printf '%*s%s: %s\n' "${indent}" '' "${name}" "${value}"
}

yaml_image_pull_secrets() {
  local indent="$1" secret="${2:-${E2E_IMAGE_PULL_SECRET:-}}"
  [ -z "${secret}" ] && return 0
  printf '%*simagePullSecrets:\n' "${indent}" ''
  printf '%*s- name: %s\n' "$((indent + 2))" '' "${secret}"
}

yaml_node_selector() {
  local indent="$1" key="${2:-}" value="${3:-}"
  [ -z "${key}" ] && return 0
  if [ -z "${value}" ]; then
    log "node selector key ${key} requires a value"
    exit "${E2E_SKIP_RC}"
  fi
  printf '%*snodeSelector:\n' "${indent}" ''
  printf '%*s%s: %s\n' "$((indent + 2))" '' "${key}" "${value}"
}

yaml_storage_class() {
  local indent="$1" storage_class="${2:-}"
  [ -z "${storage_class}" ] && return 0
  printf '%*sstorageClassName: %s\n' "${indent}" '' "${storage_class}"
}

yaml_resource_limit() {
  local indent="$1" name="${2:-}" value="${3:-1}"
  [ -z "${name}" ] && return 0
  printf '%*s%s: "%s"\n' "${indent}" '' "${name}" "${value}"
}

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
  local attempts=0 max=20 delay=120 rc out
  while [ "${attempts}" -lt "${max}" ]; do
    if out="$(printf '%s' "${data}" | $kfn "${verb}" -f - "$@" 2>&1)"; then
      printf '%s' "${out}"
      return 0
    fi
    rc=$?
    if ! echo "${out}" | grep -qE 'failed calling webhook|x509|connection refused|EOF|context deadline exceeded|webhook.* connect: connection refused|failed to download openapi|openapi'; then
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
retry_apply()  { _retry_kubectl_stdin "$1" apply "${@:2}"; }

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
