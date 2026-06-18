#!/usr/bin/env bash
# Smoke test: log to MLflow as a real user, THROUGH the OAuth proxy — browser-free.
#
# Drives the platform's standard OAuth **authorization code** flow (with PKCE)
# from the shell: it starts the flow, logs in via the local connector with an
# RSA-encrypted password (exactly as the login page does), and gets back an auth
# code. From that code it derives, and exercises, both documented credentials:
#
#   1. Bearer token  — exchange the code for a Dex id token, send it as
#                      Authorization: Bearer (needs --skip-jwt-bearer-tokens on
#                      the MLflow proxy; the test SKIPs this leg if it is off).
#   2. Session cookie — hand the code to the MLflow proxy callback to obtain the
#                      _oauth2_proxy cookie (works with no platform changes).
#
# Each leg logs a run over the platform route (i.e. through oauth2-proxy, never
# the container port) and asserts the run owner equals the caller's identity.
# No ROPC/password grant, no ServiceAccount, no direct container-port access.
#
# Required env:
#   PLATFORM_ADDRESS   e.g. https://192.168.142.163
#   CLUSTER            e.g. g1-c1-x86
#   MLFLOW_USERNAME    platform username (ideally a dedicated service account)
#   MLFLOW_PASSWORD    that user's password
# Optional env:
#   DEX_CLIENT_ID      OAuth client id (enables the bearer-token leg; default: alauda-auth)
#   DEX_CLIENT_SECRET  that client's secret (enables the bearer-token leg)
#   MLFLOW_WORKSPACE   target workspace namespace (default: mlops-demo-e2e)
set -euo pipefail

: "${PLATFORM_ADDRESS:?set PLATFORM_ADDRESS, e.g. https://192.168.142.163}"
: "${CLUSTER:?set CLUSTER, e.g. g1-c1-x86}"
: "${MLFLOW_USERNAME:?set MLFLOW_USERNAME}"
: "${MLFLOW_PASSWORD:?set MLFLOW_PASSWORD}"
DEX_CLIENT_ID="${DEX_CLIENT_ID:-alauda-auth}"
WORKSPACE="${MLFLOW_WORKSPACE:-mlops-demo-e2e}"
P="${PLATFORM_ADDRESS%/}"
REDIRECT_URI="$P/oauth2/callback"           # any URI the client has registered
BASE="$P/clusters/${CLUSTER}/mlflow/api/2.0/mlflow"

TMP="$(mktemp -d)"
CLEAN_HDR=(); CLEAN_EID=()                  # parallel arrays of (auth header, experiment id) to delete on exit
cleanup() {
  local i
  for i in "${!CLEAN_EID[@]}"; do
    curl -fsSk -H "${CLEAN_HDR[$i]}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
      -X POST "$BASE/experiments/delete" -d "{\"experiment_id\":\"${CLEAN_EID[$i]}\"}" >/dev/null 2>&1 || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

b64url_decode() { local d="$1"; d="${d//-/+}"; d="${d//_/\/}"; printf '%s%s' "$d" "$(printf '%*s' $(((4 - ${#d} % 4) % 4)) '' | tr ' ' '=')" | base64 -d 2>/dev/null; }

# RSA-encrypt {"ts","password"} with a fresh /dex/pubkey (PKCS#1 v1.5), as the login page does.
rsa_password() {
  local pk ts
  pk="$(curl -fsSk "$P/dex/pubkey")"; ts="$(echo "$pk" | jq -r .ts)"
  echo "$pk" | jq -r .pubkey > "$TMP/pub.pem"
  printf '{"ts":"%s","password":"%s"}' "$ts" "$MLFLOW_PASSWORD" \
    | openssl pkeyutl -encrypt -pubin -inkey "$TMP/pub.pem" -pkeyopt rsa_padding_mode:pkcs1 | openssl base64 -A
}

# Log a run + assert the owner. $1=label  $2=auth header (Authorization/Cookie)  $3=expected owner
run_and_assert() {
  local label="$1" header="$2" expect="$3" exp eid rid owner status param run
  exp="uit-${label}-$$-${RANDOM}"
  eid="$(curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
         -X POST "$BASE/experiments/create" -d "{\"name\":\"${exp}\"}" | jq -r '.experiment_id // empty')"
  [ -n "$eid" ] || { echo "FAIL[$label]: experiment not created"; return 1; }
  CLEAN_HDR+=("$header"); CLEAN_EID+=("$eid")
  rid="$(curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
         -X POST "$BASE/runs/create" -d "{\"experiment_id\":\"${eid}\",\"start_time\":1700000000000}" | jq -r '.run.info.run_id // empty')"
  [ -n "$rid" ] || { echo "FAIL[$label]: run not created"; return 1; }
  curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
    -X POST "$BASE/runs/log-parameter" -d "{\"run_id\":\"${rid}\",\"key\":\"model_name\",\"value\":\"qwen3-0.6b\"}" >/dev/null
  curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
    -X POST "$BASE/runs/log-metric" -d "{\"run_id\":\"${rid}\",\"key\":\"loss\",\"value\":0.123,\"timestamp\":1700000000000,\"step\":1}" >/dev/null
  curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" -H 'Content-Type: application/json' \
    -X POST "$BASE/runs/update" -d "{\"run_id\":\"${rid}\",\"status\":\"FINISHED\",\"end_time\":1700000005000}" >/dev/null
  run="$(curl -fsSk -H "$header" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" "$BASE/runs/get?run_id=${rid}")"
  owner="$(printf '%s' "$run" | jq -r '.run.info.user_id')"
  status="$(printf '%s' "$run" | jq -r '.run.info.status')"
  param="$(printf '%s' "$run" | jq -r '.run.data.params[] | select(.key=="model_name") | .value')"
  echo "  [$label] run_id=${rid} owner=${owner} status=${status} model_name=${param}"
  [ "$status" = "FINISHED" ]  || { echo "FAIL[$label]: run not FINISHED"; return 1; }
  [ "$param" = "qwen3-0.6b" ] || { echo "FAIL[$label]: param not logged"; return 1; }
  [ "$owner" = "$expect" ]    || { echo "FAIL[$label]: owner '${owner}' != expected '${expect}'"; return 1; }
}

EXPECT_OWNER="$MLFLOW_USERNAME"

# ---------------------------------------------------------------------------
# Leg 1: bearer token (authorization_code + PKCE -> id_token)
# ---------------------------------------------------------------------------
if [ -n "${DEX_CLIENT_SECRET:-}" ]; then
  echo "== leg 1: mint id token via authorization_code + PKCE =="
  V="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=' | cut -c1-64)"
  C="$(printf %s "$V" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  RU="$(jq -rn --arg u "$REDIRECT_URI" '$u|@uri')"; SC="$(jq -rn '"openid email groups offline_access"|@uri')"
  REQ="$(curl -fsSk "$P/dex/api/v1/authorize?client_id=${DEX_CLIENT_ID}&redirect_uri=${RU}&response_type=code&scope=${SC}&state=cli&code_challenge=${C}&code_challenge_method=S256" | jq -r '.req // empty')"
  [ -n "$REQ" ] || { echo "FAIL: authorize returned no req (PKCE/client issue?)"; exit 1; }
  ENC="$(rsa_password)"
  CODE="$(curl -fsSk -X POST "$P/dex/api/v1/authorize/local?req=${REQ}" -H 'Content-Type: application/json' \
          --data "$(jq -nc --arg a "$MLFLOW_USERNAME" --arg p "$ENC" '{account:$a,password:$p}')" \
          | jq -r '.redirect_url // empty' | sed -E 's/.*code=([^&]+).*/\1/')"
  [ -n "$CODE" ] || { echo "FAIL: login returned no auth code (captcha triggered or bad credentials?)"; exit 1; }
  ID_TOKEN="$(curl -fsSk "$P/dex/token" -d grant_type=authorization_code -d code="$CODE" \
              --data-urlencode redirect_uri="$REDIRECT_URI" -d code_verifier="$V" \
              -d client_id="${DEX_CLIENT_ID}" --data-urlencode client_secret="${DEX_CLIENT_SECRET}" | jq -r '.id_token // empty')"
  [ -n "$ID_TOKEN" ] || { echo "FAIL: token exchange returned no id_token"; exit 1; }
  EXPECT_OWNER="$(b64url_decode "$(printf '%s' "$ID_TOKEN" | cut -d. -f2)" | jq -r '.email // .preferred_username // .name // .sub')"
  echo "  caller identity: ${EXPECT_OWNER}"
  # Is the proxy configured to accept bearer tokens?
  HTTP="$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${ID_TOKEN}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE}" "$BASE/experiments/search?max_results=1")"
  if [ "$HTTP" = "200" ]; then
    run_and_assert "token" "Authorization: Bearer ${ID_TOKEN}" "$EXPECT_OWNER"
    echo "PASS: bearer-token method (authorization_code + PKCE)"
  else
    echo "SKIP: bearer-token method — proxy returned HTTP ${HTTP} (enable --skip-jwt-bearer-tokens on the MLflow proxy)"
  fi
else
  echo "SKIP: bearer-token method — set DEX_CLIENT_SECRET to exercise it"
fi

# ---------------------------------------------------------------------------
# Leg 2: session cookie (no platform changes)
# ---------------------------------------------------------------------------
echo "== leg 2: mint _oauth2_proxy cookie via the proxy login =="
JAR="$TMP/proxyjar.txt"; : > "$JAR"
LOC="$(curl -sk -c "$JAR" -D - -o /dev/null "$P/clusters/${CLUSTER}/mlflow/" | awk 'BEGIN{IGNORECASE=1}/^location:/{print $2}' | tr -d '\r')"
QS="${LOC#*\?}"
[ "$QS" != "$LOC" ] || { echo "FAIL: MLflow route did not redirect to login"; exit 1; }
REQ="$(curl -sk -b "$JAR" -c "$JAR" "$P/dex/api/v1/authorize?${QS}" | jq -r '.req // empty')"
[ -n "$REQ" ] || { echo "FAIL: proxy authorize returned no req"; exit 1; }
ENC="$(rsa_password)"
CB="$(curl -sk -b "$JAR" -c "$JAR" -X POST "$P/dex/api/v1/authorize/local?req=${REQ}" -H 'Content-Type: application/json' \
      --data "$(jq -nc --arg a "$MLFLOW_USERNAME" --arg p "$ENC" '{account:$a,password:$p}')" | jq -r '.redirect_url // empty')"
[ -n "$CB" ] || { echo "FAIL: proxy login returned no callback url"; exit 1; }
curl -sk -b "$JAR" -c "$JAR" -o /dev/null "$CB"
COOKIE="$(awk -F'\t' '$6 ~ /^_oauth2_proxy/{printf "%s=%s; ",$6,$7}' "$JAR" | sed 's/; $//')"
[ -n "$COOKIE" ] || { echo "FAIL: no _oauth2_proxy cookie minted"; exit 1; }
run_and_assert "cookie" "Cookie: ${COOKIE}" "$EXPECT_OWNER"
echo "PASS: session-cookie method (no platform changes)"

echo "DONE: authenticated to MLflow through the OAuth proxy as '${EXPECT_OWNER}' — browser-free, no container-port access"
