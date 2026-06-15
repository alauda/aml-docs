#!/usr/bin/env bash
# Smoke test: log to MLflow with a platform **user identity token**.
#
# Exercises the MLflow `kubernetes-auth` plugin's `user_identity_token` mode:
# the server takes the caller identity from the bearer token's claims and records
# the run under that user. No ServiceAccount and no extra in-cluster Service are
# created — the MLflow server is reached through the platform Kubernetes API proxy
# (the same `…/kubernetes/<cluster>` entry point used for any K8s call), and the
# caller identity is forwarded to MLflow via `X-Forwarded-Access-Token`.
#
# Required env:
#   PLATFORM_ADDRESS   e.g. https://192.168.142.163
#   CLUSTER            e.g. g1-c1-x86
#   MLFLOW_USER_TOKEN  a platform user identity token (JWT with an `email` claim)
# Optional env:
#   MLFLOW_WORKSPACE   target workspace namespace (default: mlops-demo-e2e)
#   MLFLOW_NS          namespace of the MLflow server (default: kubeflow)
set -euo pipefail

: "${PLATFORM_ADDRESS:?set PLATFORM_ADDRESS, e.g. https://192.168.142.163}"
: "${CLUSTER:?set CLUSTER, e.g. g1-c1-x86}"
: "${MLFLOW_USER_TOKEN:?set MLFLOW_USER_TOKEN to a platform user identity token}"
WORKSPACE="${MLFLOW_WORKSPACE:-mlops-demo-e2e}"
MLFLOW_NS="${MLFLOW_NS:-kubeflow}"

KAPI="${PLATFORM_ADDRESS%/}/kubernetes/${CLUSTER}"
TOKEN="${MLFLOW_USER_TOKEN}"

# Identity the server should attribute the run to (first email claim in the JWT).
EMAIL="$(printf '%s' "${TOKEN}" | cut -d. -f2 | tr '_-' '/+' \
  | { b="$(cat)"; printf '%s%s' "$b" "$(printf '%*s' $(( (4 - ${#b} % 4) % 4 )) '' | tr ' ' '=')"; } \
  | base64 -d 2>/dev/null | jq -r '.email // .preferred_username // .name // .sub')"
echo "caller identity: ${EMAIL}"

# Authenticate to the platform K8s API with the user token; locate the MLflow pod.
POD="$(curl -fsSk -H "Authorization: Bearer ${TOKEN}" \
  "${KAPI}/api/v1/namespaces/${MLFLOW_NS}/pods?labelSelector=app%3Dmlflow-tracking-server" \
  | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name' | head -1)"
[ -n "${POD}" ] || { echo "FAIL: no running mlflow-tracking-server pod in ${MLFLOW_NS}"; exit 1; }
echo "mlflow pod: ${POD}"

# Reach the MLflow app port (5000) through the K8s API pod proxy, bypassing the
# browser OAuth proxy. Authorization authenticates us to the K8s API; the MLflow
# server reads our identity from X-Forwarded-Access-Token.
BASE="${KAPI}/api/v1/namespaces/${MLFLOW_NS}/pods/${POD}:5000/proxy/api/2.0/mlflow"
hdr=(-H "Authorization: Bearer ${TOKEN}"
     -H "X-Forwarded-Access-Token: ${TOKEN}"
     -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}"
     -H "Content-Type: application/json")

api() { # api <method> <path> [json-body]
  curl -fsSk "${hdr[@]}" -X "$1" "${BASE}/$2" ${3:+-d "$3"}
}

EXP_NAME="uit-smoke-$$"
echo "== create experiment '${EXP_NAME}' =="
EID="$(api POST experiments/create "{\"name\":\"${EXP_NAME}\"}" | jq -r '.experiment_id')"
[ -n "${EID}" ] && [ "${EID}" != null ] || { echo "FAIL: experiment not created"; exit 1; }

cleanup() { api POST experiments/delete "{\"experiment_id\":\"${EID}\"}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== create run, log params + metrics =="
RID="$(api POST runs/create "{\"experiment_id\":\"${EID}\",\"start_time\":1700000000000}" | jq -r '.run.info.run_id')"
[ -n "${RID}" ] && [ "${RID}" != null ] || { echo "FAIL: run not created"; exit 1; }
api POST runs/log-parameter "{\"run_id\":\"${RID}\",\"key\":\"model_name\",\"value\":\"qwen3-0.6b\"}" >/dev/null
for s in 1 2 3; do
  api POST runs/log-metric "{\"run_id\":\"${RID}\",\"key\":\"loss\",\"value\":$(awk "BEGIN{print 2.0*(0.9^$s)}"),\"timestamp\":1700000000000,\"step\":${s}}" >/dev/null
done
api POST runs/update "{\"run_id\":\"${RID}\",\"status\":\"FINISHED\",\"end_time\":1700000005000}" >/dev/null

echo "== read back and assert =="
RUN="$(api GET "runs/get?run_id=${RID}")"
OWNER="$(printf '%s' "${RUN}" | jq -r '.run.info.user_id')"
STATUS="$(printf '%s' "${RUN}" | jq -r '.run.info.status')"
PARAM="$(printf '%s' "${RUN}" | jq -r '.run.data.params[] | select(.key=="model_name") | .value')"
METRIC="$(printf '%s' "${RUN}" | jq -r '.run.data.metrics[] | select(.key=="loss") | .key' | head -1)"

echo "  run_id=${RID} owner=${OWNER} status=${STATUS} model_name=${PARAM} metric=${METRIC}"
[ "${STATUS}" = "FINISHED" ]      || { echo "FAIL: run not FINISHED"; exit 1; }
[ "${PARAM}" = "qwen3-0.6b" ]     || { echo "FAIL: param not logged"; exit 1; }
[ "${METRIC}" = "loss" ]          || { echo "FAIL: metric not logged"; exit 1; }
[ "${OWNER}" = "${EMAIL}" ]       || { echo "FAIL: run owner '${OWNER}' != caller identity '${EMAIL}'"; exit 1; }

echo "PASS: logged to MLflow as user identity '${EMAIL}' (no ServiceAccount, no direct Service)"
