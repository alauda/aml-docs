#!/usr/bin/env bash
# Smoke test: log to MLflow as a real user, THROUGH the OAuth proxy.
#
# Mints a short-lived Dex **id token** from a long-lived **refresh token** (the
# refresh-token grant), then logs a run to MLflow over the platform route — i.e.
# through oauth2-proxy, never the container port. Asserts the run owner equals the
# token's user identity.
#
# Requires the MLflow oauth2-proxy to accept OIDC bearer tokens
# (auth.oauth.extraArgs: ["--skip-jwt-bearer-tokens=true"]).
#
# Required env:
#   PLATFORM_ADDRESS      e.g. https://192.168.142.163
#   CLUSTER               e.g. g1-c1-x86
#   MLFLOW_REFRESH_TOKEN  a Dex refresh token (from an offline_access login)
#   DEX_CLIENT_ID         platform OAuth client id (e.g. alauda-auth)
#   DEX_CLIENT_SECRET     that client's secret
# Optional env:
#   MLFLOW_WORKSPACE      target workspace namespace (default: mlops-demo-e2e)
set -euo pipefail

: "${PLATFORM_ADDRESS:?set PLATFORM_ADDRESS, e.g. https://192.168.142.163}"
: "${CLUSTER:?set CLUSTER, e.g. g1-c1-x86}"
: "${MLFLOW_REFRESH_TOKEN:?set MLFLOW_REFRESH_TOKEN to a Dex refresh token}"
: "${DEX_CLIENT_ID:?set DEX_CLIENT_ID, e.g. alauda-auth}"
: "${DEX_CLIENT_SECRET:?set DEX_CLIENT_SECRET}"
WORKSPACE="${MLFLOW_WORKSPACE:-mlops-demo-e2e}"
P="${PLATFORM_ADDRESS%/}"

b64url_decode() { local d="$1"; d="${d//-/+}"; d="${d//_/\/}"; printf '%s%s' "$d" "$(printf '%*s' $(((4 - ${#d} % 4) % 4)) '' | tr ' ' '=')" | base64 -d 2>/dev/null; }

echo "== mint id token via refresh-token grant =="
ID_TOKEN="$(curl -fsSk "$P/dex/token" \
  -d grant_type=refresh_token \
  --data-urlencode "refresh_token=${MLFLOW_REFRESH_TOKEN}" \
  -d client_id="${DEX_CLIENT_ID}" \
  --data-urlencode "client_secret=${DEX_CLIENT_SECRET}" \
  | jq -r '.id_token')"
[ -n "${ID_TOKEN}" ] && [ "${ID_TOKEN}" != null ] || { echo "FAIL: no id_token from refresh-token grant"; exit 1; }
EMAIL="$(b64url_decode "$(printf '%s' "$ID_TOKEN" | cut -d. -f2)" | jq -r '.email // .preferred_username // .name // .sub')"
echo "caller identity: ${EMAIL}"

# Through the OAuth proxy: the platform MLflow route, with the id token as a bearer.
BASE="$P/clusters/${CLUSTER}/mlflow/api/2.0/mlflow"
hdr=(-H "Authorization: Bearer ${ID_TOKEN}"
     -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}"
     -H "Content-Type: application/json")
api() { curl -fsSk "${hdr[@]}" -X "$1" "${BASE}/$2" ${3:+-d "$3"}; }

EXP="uit-smoke-$$"
echo "== create experiment '${EXP}' =="
EID="$(api POST experiments/create "{\"name\":\"${EXP}\"}" | jq -r '.experiment_id')"
[ -n "${EID}" ] && [ "${EID}" != null ] || { echo "FAIL: experiment not created (is --skip-jwt-bearer-tokens enabled?)"; exit 1; }
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
echo "  run_id=${RID} owner=${OWNER} status=${STATUS} model_name=${PARAM}"
[ "${STATUS}" = "FINISHED" ]   || { echo "FAIL: run not FINISHED"; exit 1; }
[ "${PARAM}" = "qwen3-0.6b" ]  || { echo "FAIL: param not logged"; exit 1; }
[ "${OWNER}" = "${EMAIL}" ]    || { echo "FAIL: run owner '${OWNER}' != caller identity '${EMAIL}'"; exit 1; }

echo "PASS: logged to MLflow as '${EMAIL}' through the OAuth proxy (refresh-token grant; no cookie, no container-port access)"
