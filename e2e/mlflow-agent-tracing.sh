#!/usr/bin/env bash
# E2E: invoke a LangChain agent and verify its MLflow trace.
#
# Connection (choose one):
#   MLFLOW_TRACKING_URI     MLflow route, for example https://<platform>/clusters/x86/mlflow; or
#   PLATFORM_ADDRESS, CLUSTER
#                           values used to derive the MLflow route
# Required:
#   MLFLOW_WORKSPACE        target workspace namespace
#   AGENT_MODEL_BASE_URL    OpenAI-compatible endpoint ending in /v1
#   AGENT_MODEL_ID          model ID returned by the endpoint's /models API
#
# Authentication (choose one):
#   MLFLOW_TRACKING_TOKEN   Dex id token accepted by the MLflow OAuth proxy; or
#   MLFLOW_PROXY_COOKIE     existing _oauth2_proxy cookie; or
#   PLATFORM_ADDRESS, CLUSTER, MLFLOW_USERNAME, MLFLOW_PASSWORD
#                           credentials used to mint a temporary proxy cookie
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/lib.sh"

require_env MLFLOW_WORKSPACE "workspace namespace for the trace experiment"
require_env AGENT_MODEL_BASE_URL "OpenAI-compatible model endpoint ending in /v1"
require_env AGENT_MODEL_ID "model ID returned by the endpoint's /models API"

if [ -z "${MLFLOW_TRACKING_URI:-}" ]; then
  require_env PLATFORM_ADDRESS "needed to derive MLFLOW_TRACKING_URI"
  require_env CLUSTER "platform cluster name, for example x86"
  export MLFLOW_TRACKING_URI="${PLATFORM_ADDRESS%/}/clusters/${CLUSTER}/mlflow"
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT
umask 077

# Local development environments can have a proxy configured for public
# traffic. The platform route is internal and must be contacted directly.
if [ -n "${PLATFORM_ADDRESS:-}" ]; then
  PLATFORM_HOST="${PLATFORM_ADDRESS#*://}"
  PLATFORM_HOST="${PLATFORM_HOST%%/*}"
  PLATFORM_HOST="${PLATFORM_HOST%%:*}"
  case ",${NO_PROXY:-}," in
    *",${PLATFORM_HOST},"*) ;;
    *) export NO_PROXY="${NO_PROXY:+${NO_PROXY},}${PLATFORM_HOST}" ;;
  esac
  export no_proxy="${NO_PROXY}"
fi

mint_proxy_cookie() {
  require_env PLATFORM_ADDRESS "needed to mint an MLflow proxy session"
  require_env CLUSTER "platform cluster name, for example x86"
  require_env MLFLOW_USERNAME "platform username"
  require_env MLFLOW_PASSWORD "platform password"

  local platform route jar location query request public_key timestamp encrypted callback
  platform="${PLATFORM_ADDRESS%/}"
  route="${platform}/clusters/${CLUSTER}/mlflow"
  jar="${TMP}/cookies"

  location="$(curl -fsSk -c "${jar}" -D - -o /dev/null "${route}/" \
    | awk 'BEGIN{IGNORECASE=1}/^location:/{print $2}' | tr -d '\r')"
  query="${location#*\?}"
  [ "${query}" != "${location}" ] || { log "MLflow route did not redirect to login"; return 1; }

  request="$(curl -fsSk -b "${jar}" -c "${jar}" \
    "${platform}/dex/api/v1/authorize?${query}" | jq -r '.req // empty')"
  [ -n "${request}" ] || { log "Dex authorize response did not contain a request ID"; return 1; }

  public_key="$(curl -fsSk "${platform}/dex/pubkey")"
  timestamp="$(printf '%s' "${public_key}" | jq -r '.ts')"
  printf '%s' "${public_key}" | jq -r '.pubkey' > "${TMP}/dex-public.pem"
  encrypted="$(jq -nc --arg ts "${timestamp}" --arg password "${MLFLOW_PASSWORD}" \
    '{ts:$ts,password:$password}' \
    | openssl pkeyutl -encrypt -pubin -inkey "${TMP}/dex-public.pem" \
        -pkeyopt rsa_padding_mode:pkcs1 \
    | openssl base64 -A)"

  callback="$(curl -fsSk -b "${jar}" -c "${jar}" -X POST \
    "${platform}/dex/api/v1/authorize/local?req=${request}" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg account "${MLFLOW_USERNAME}" --arg password "${encrypted}" \
      '{account:$account,password:$password}')" \
    | jq -r '.redirect_url // empty')"
  [ -n "${callback}" ] || { log "Dex login did not return the MLflow proxy callback"; return 1; }

  curl -fsSk -b "${jar}" -c "${jar}" -o /dev/null "${callback}"
  MLFLOW_PROXY_COOKIE="$(awk -F'\t' '$6 ~ /^_oauth2_proxy/{printf "%s=%s; ",$6,$7}' "${jar}" \
    | sed 's/; $//')"
  [ -n "${MLFLOW_PROXY_COOKIE}" ] || { log "MLflow proxy session cookie was not created"; return 1; }
  export MLFLOW_PROXY_COOKIE
}

if [ -z "${MLFLOW_TRACKING_TOKEN:-}" ] && [ -z "${MLFLOW_PROXY_COOKIE:-}" ]; then
  log "minting a temporary MLflow proxy session"
  mint_proxy_cookie
fi

export MLFLOW_TRACKING_INSECURE_TLS="${MLFLOW_TRACKING_INSECURE_TLS:-true}"

command -v uv >/dev/null 2>&1 || { log "uv is required to run the isolated Python test"; exit 1; }

log "running LangChain agent tracing test"
uv run --no-project --python "${E2E_PYTHON:-3.12}" \
  --with 'mlflow[genai]==3.13.0' \
  --with 'langchain>=1,<2' \
  --with 'langchain-openai>=1,<2' \
  "${HERE}/mlflow-agent-tracing.py"
