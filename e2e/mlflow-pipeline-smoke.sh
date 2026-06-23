#!/usr/bin/env bash
# Smoke test (roadmap 8.1.2 — AIP-to-MLflow backend integration):
# submit a Kubeflow Pipeline whose single container step opens an MLflow run from
# the *pipeline-run context*, logs params + a metric + a tiny artifact, and tags
# the MLflow run with the KFP pipeline run id — then VERIFY over the MLflow REST
# API that the run exists with the expected param/metric and the KFP-run-id tag.
#
# Why this shape (no kfp SDK, no PyPI):
#   - The pipeline is a KFP v2 *container component* (e2e/assets/mlflow-pipeline.yaml),
#     so the step image runs directly with NO `pip install kfp` bootstrap. The step
#     image is mlops/mlflow-acp (it already ships mlflow), so `import mlflow` works.
#   - It is submitted through the KFP v2 REST API with curl+jq (upload IR -> create
#     run), not compiled on the runner.
#   - Auth to MLflow uses a workspace ServiceAccount token against the proxy-bypass
#     in-cluster Service (authorizationMode=user_identity_token) — no oauth2-proxy /
#     Dex / ROPC. The token is injected as MLFLOW_TRACKING_TOKEN via the IR's
#     kubernetes platform spec (secretAsEnv).
#
# Exit codes: 0 pass; 77 skip (KFP or MLflow unreachable / missing prereq); 1 fail.
#
# Env (all have defaults for g1-c1-x86):
#   KUBE_CONTEXT     kube context                 (default: g1-c1-x86-admin@g1-c1-x86)
#   MLFLOW_NS        ns of the MLflow tracking svc(default: kubeflow)
#   MLFLOW_DIRECT_SVC proxy-bypass Service name   (default: mlflow-e2e-direct)
#   WORKSPACE_NS     MLflow workspace ns (mlflow-enabled=true) + its SA
#                                                 (default: mlflow-e2e)
#   WORKSPACE_SA     workspace ServiceAccount     (default: mlflow-e2e)
#   RUN_NS           KFP run namespace: a profile ns whose mlpipeline-minio-artifact
#                    secret holds WORKING MinIO creds (default: modelcar-pipeline).
#   KFP_USERID       multi-user identity header   (default: admin@cpaas.io)
#   EXPERIMENT       MLflow experiment name       (default: aip-mlflow-pipeline-8.1.2)
#   RUN_AS_USER      non-zero UID for the workflow podSpecPatch workaround
#                    (default: 8737); see "cluster-environment workarounds" below.
#
# Cluster-environment workarounds (NOT part of the integration; this KFP install
# has two defects that block ANY KFP v2 run):
#   1. Workflow pods set securityContext.runAsNonRoot=true with no runAsUser, so
#      the root argoexec init/wait image is rejected (CreateContainerConfigError).
#      Fix: patch workflow.spec.podSpecPatch to add runAsUser, and delete the
#      already-errored driver pods so Argo recreates them with the patch.
#   2. Some profile namespaces carry stale MinIO creds in mlpipeline-minio-artifact
#      ("access key ID ... does not exist"). Fix: run in a namespace with valid
#      creds (modelcar-pipeline / zgsu-ns1 on g1-c1-x86).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_RC=77

KUBE_CONTEXT="${KUBE_CONTEXT:-g1-c1-x86-admin@g1-c1-x86}"
MLFLOW_NS="${MLFLOW_NS:-kubeflow}"
MLFLOW_DIRECT_SVC="${MLFLOW_DIRECT_SVC:-mlflow-e2e-direct}"
WORKSPACE_NS="${WORKSPACE_NS:-mlflow-e2e}"
WORKSPACE_SA="${WORKSPACE_SA:-mlflow-e2e}"
RUN_NS="${RUN_NS:-modelcar-pipeline}"
KFP_USERID="${KFP_USERID:-admin@cpaas.io}"
RUN_AS_USER="${RUN_AS_USER:-8737}"
TOKEN_SECRET="mlflow-pipeline-token"
STAMP="$(date +%s)"
# Unique experiment name per run: MLflow soft-deletes experiments, and refuses to
# reuse a deleted name, so a fresh name keeps repeated smoke runs collision-free.
EXPERIMENT="${EXPERIMENT:-aip-mlflow-pipeline-8.1.2-${STAMP}}"

kc() { kubectl --context "${KUBE_CONTEXT}" "$@"; }
log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die_skip() { log "SKIP: $*"; exit "${SKIP_RC}"; }
die_fail() { log "FAIL: $*"; exit 1; }

command -v jq >/dev/null   || die_skip "jq not found"
command -v curl >/dev/null || die_skip "curl not found"
kc version --request-timeout=10s >/dev/null 2>&1 || die_skip "kube context ${KUBE_CONTEXT} unreachable"
kc -n "${MLFLOW_NS}" get svc "${MLFLOW_DIRECT_SVC}" >/dev/null 2>&1 \
  || die_skip "MLflow proxy-bypass Service ${MLFLOW_NS}/${MLFLOW_DIRECT_SVC} not found"
kc -n "${MLFLOW_NS}" get svc ml-pipeline >/dev/null 2>&1 \
  || die_skip "KFP ml-pipeline Service not found in ${MLFLOW_NS}"
kc -n "${RUN_NS}" get secret mlpipeline-minio-artifact >/dev/null 2>&1 \
  || die_skip "run namespace ${RUN_NS} lacks mlpipeline-minio-artifact (KFP runs would not start)"
# Optional workaround #2: reconcile the artifact creds. Set MINIO_ACCESSKEY /
# MINIO_SECRETKEY to the values your SeaweedFS/MinIO actually accepts (on
# g1-c1-x86: minio / minio123) when the profile-synced secret is stale.
if [ -n "${MINIO_ACCESSKEY:-}" ] && [ -n "${MINIO_SECRETKEY:-}" ]; then
  kc -n "${RUN_NS}" create secret generic mlpipeline-minio-artifact \
     --from-literal=accesskey="${MINIO_ACCESSKEY}" --from-literal=secretkey="${MINIO_SECRETKEY}" \
     --dry-run=client -o yaml | kc -n "${RUN_NS}" apply -f - >/dev/null 2>&1 \
     && log "reconciled mlpipeline-minio-artifact in ${RUN_NS}"
fi

# --- port-forwards -----------------------------------------------------------
PF_PIDS=()
cleanup() {
  for p in "${PF_PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  [ -n "${PID:-}" ]  && curl -s -H "kubeflow-userid: ${KFP_USERID}" -X DELETE "${KFP}/apis/v2beta1/pipelines/${PID}" >/dev/null 2>&1
  [ -n "${RID:-}" ]  && curl -s -H "kubeflow-userid: ${KFP_USERID}" -X DELETE "${KFP}/apis/v2beta1/runs/${RID}" >/dev/null 2>&1
  [ -n "${EID:-}" ]  && curl -s -H "${AUTH}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE_NS}" -H 'Content-Type: application/json' \
                          -X POST "${MLF}/api/2.0/mlflow/experiments/delete" -d "{\"experiment_id\":\"${EID}\"}" >/dev/null 2>&1
  kc -n "${RUN_NS}" delete secret "${TOKEN_SECRET}" --ignore-not-found >/dev/null 2>&1
}
trap cleanup EXIT

KFP_PORT=$(( (RANDOM % 2000) + 28000 )); MLF_PORT=$(( KFP_PORT + 1 ))
kc -n "${MLFLOW_NS}" port-forward "svc/ml-pipeline" "${KFP_PORT}:8888" >/tmp/pf-kfp-$STAMP.log 2>&1 & PF_PIDS+=("$!")
kc -n "${MLFLOW_NS}" port-forward "svc/${MLFLOW_DIRECT_SVC}" "${MLF_PORT}:5000" >/tmp/pf-mlf-$STAMP.log 2>&1 & PF_PIDS+=("$!")
KFP="http://127.0.0.1:${KFP_PORT}"; MLF="http://127.0.0.1:${MLF_PORT}"
for i in $(seq 1 15); do
  curl -s -o /dev/null "${KFP}/apis/v2beta1/healthz" && break; sleep 1
done
[ "$(curl -s -o /dev/null -w '%{http_code}' "${KFP}/apis/v2beta1/healthz")" = "200" ] \
  || die_skip "KFP API not reachable via port-forward"

# --- workspace SA token + secret in the run namespace ------------------------
TOK="$(kc -n "${WORKSPACE_NS}" create token "${WORKSPACE_SA}" --duration=7200s 2>/dev/null)"
[ -n "${TOK}" ] || die_skip "could not mint token for ${WORKSPACE_NS}/${WORKSPACE_SA}"
AUTH="Authorization: Bearer ${TOK}"
# preflight MLflow reachability + auth
mh="$(curl -s -o /dev/null -w '%{http_code}' -H "${AUTH}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE_NS}" \
       "${MLF}/api/2.0/mlflow/experiments/search?max_results=1")"
[ "${mh}" = "200" ] || die_skip "MLflow direct Service auth returned HTTP ${mh} (expected 200)"
kc -n "${RUN_NS}" delete secret "${TOKEN_SECRET}" --ignore-not-found >/dev/null 2>&1
kc -n "${RUN_NS}" create secret generic "${TOKEN_SECRET}" --from-literal=token="${TOK}" >/dev/null \
  || die_fail "could not create token secret in ${RUN_NS}"

# --- generate the IR (image/uri/workspace/experiment/secret are all baked in) -
MLFLOW_TRACKING_URI="http://${MLFLOW_DIRECT_SVC}.${MLFLOW_NS}:5000" \
MLFLOW_WORKSPACE="${WORKSPACE_NS}" MLFLOW_EXPERIMENT_NAME="${EXPERIMENT}" \
MLFLOW_TOKEN_SECRET="${TOKEN_SECRET}" \
  bash "${HERE}/assets/build-pipeline-ir.sh" /tmp/mlflow-pipeline-$STAMP.yaml >/dev/null
IR="/tmp/mlflow-pipeline-$STAMP.yaml"

# --- upload pipeline + create experiment + run -------------------------------
PNAME="aip-mlflow-8-1-2-${STAMP}"
PID="$(curl -s -H "kubeflow-userid: ${KFP_USERID}" -F "uploadfile=@${IR};type=application/x-yaml" \
       "${KFP}/apis/v2beta1/pipelines/upload?name=${PNAME}&namespace=${RUN_NS}" | jq -r '.pipeline_id // empty')"
[ -n "${PID}" ] || die_fail "pipeline upload failed"
VID="$(curl -s -H "kubeflow-userid: ${KFP_USERID}" "${KFP}/apis/v2beta1/pipelines/${PID}/versions?page_size=5" \
       | jq -r '.pipeline_versions[0].pipeline_version_id')"
EID_KFP="$(curl -s -H "kubeflow-userid: ${KFP_USERID}" -H 'Content-Type: application/json' \
       -X POST "${KFP}/apis/v2beta1/experiments" -d "{\"display_name\":\"${PNAME}\",\"namespace\":\"${RUN_NS}\"}" \
       | jq -r '.experiment_id // empty')"
RID="$(curl -s -H "kubeflow-userid: ${KFP_USERID}" -H 'Content-Type: application/json' -X POST "${KFP}/apis/v2beta1/runs" \
       -d "{\"display_name\":\"${PNAME}-run\",\"experiment_id\":\"${EID_KFP}\",\"pipeline_version_reference\":{\"pipeline_id\":\"${PID}\",\"pipeline_version_id\":\"${VID}\"}}" \
       | jq -r '.run_id // empty')"
[ -n "${RID}" ] || die_fail "run creation failed"
log "KFP pipeline_id=${PID} run_id=${RID} (ns=${RUN_NS})"

# --- cluster-environment workaround #1: patch the workflow's podSpecPatch -----
# Find the Argo Workflow for this run and add runAsUser, so the root argoexec
# init/wait image is not rejected by runAsNonRoot. (No-op on a healthy install.)
WF=""
for i in $(seq 1 30); do
  WF="$(kc -n "${RUN_NS}" get workflows.argoproj.io -l "pipeline/runid=${RID}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [ -n "${WF}" ] && break; sleep 1
done
if [ -n "${WF}" ]; then
  kc -n "${RUN_NS}" patch workflow "${WF}" --type merge \
     -p "{\"spec\":{\"podSpecPatch\":\"{\\\"securityContext\\\":{\\\"runAsUser\\\":${RUN_AS_USER}}}\"}}" >/dev/null 2>&1
  log "patched workflow ${WF} podSpecPatch runAsUser=${RUN_AS_USER}"
fi

# --- wait for the run; clear any driver pods that raced the patch ------------
STATE=""
for i in $(seq 1 60); do
  BAD="$(kc -n "${RUN_NS}" get pods 2>/dev/null | awk '/aip-mlflow/ && /CreateContainerConfigError|RunContainerError/ {print $1}')"
  [ -n "${BAD}" ] && kc -n "${RUN_NS}" delete pod ${BAD} --ignore-not-found >/dev/null 2>&1
  STATE="$(curl -s -H "kubeflow-userid: ${KFP_USERID}" "${KFP}/apis/v2beta1/runs/${RID}" | jq -r '.state // empty')"
  case "${STATE}" in SUCCEEDED|FAILED|ERROR) break;; esac
  sleep 6
done
log "KFP run state=${STATE}"
[ "${STATE}" = "SUCCEEDED" ] || die_fail "KFP run did not succeed (state=${STATE})"

# --- VERIFY linkage over MLflow REST -----------------------------------------
# Find the MLflow run tagged with this KFP run id, in the named experiment.
EID="$(curl -s -H "${AUTH}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE_NS}" -H 'Content-Type: application/json' \
       -X POST "${MLF}/api/2.0/mlflow/experiments/get-by-name" -d "{\"experiment_name\":\"${EXPERIMENT}\"}" \
       | jq -r '.experiment.experiment_id // empty')"
[ -n "${EID}" ] || die_fail "MLflow experiment ${EXPERIMENT} not found"
SR="$(curl -s -H "${AUTH}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE_NS}" -H 'Content-Type: application/json' \
      -X POST "${MLF}/api/2.0/mlflow/runs/search" \
      -d "{\"experiment_ids\":[\"${EID}\"],\"filter\":\"tags.kfp_run_id = '${RID}'\",\"max_results\":1}")"
MRID="$(echo "${SR}" | jq -r '.runs[0].info.run_id // empty')"
[ -n "${MRID}" ] || die_fail "no MLflow run tagged kfp_run_id=${RID} in experiment ${EXPERIMENT}"
RG="$(curl -s -H "${AUTH}" -H "X-MLFLOW-WORKSPACE: ${WORKSPACE_NS}" "${MLF}/api/2.0/mlflow/runs/get?run_id=${MRID}")"
TAG="$(echo "${RG}" | jq -r '.run.data.tags[]   | select(.key=="kfp_run_id")     | .value')"
PARAM="$(echo "${RG}" | jq -r '.run.data.params[] | select(.key=="model_name")    | .value')"
METRIC="$(echo "${RG}" | jq -r '.run.data.metrics[]| select(.key=="final_accuracy")| .value')"
STATUS="$(echo "${RG}" | jq -r '.run.info.status')"
log "MLflow experiment_id=${EID} run_id=${MRID} status=${STATUS}"
log "  kfp_run_id tag = ${TAG}"
log "  param model_name = ${PARAM}"
log "  metric final_accuracy = ${METRIC}"

[ "${TAG}" = "${RID}" ]        || die_fail "kfp_run_id tag '${TAG}' != KFP run id '${RID}'"
[ "${PARAM}" = "demo-model" ]  || die_fail "param model_name not logged"
[ "${METRIC}" = "0.95" ]       || die_fail "metric final_accuracy not 0.95 (got '${METRIC}')"
[ "${STATUS}" = "FINISHED" ]   || die_fail "MLflow run not FINISHED"

log "PASS: KFP run ${RID} -> MLflow run ${MRID} (tag/param/metric verified; linkage established)"
