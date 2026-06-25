#!/usr/bin/env bash
# C13 — Feast first-cycle e2e SMOKE (roadmap 8.5.2 Feature Store GA).
#
# Proves a brand-new Feast deployment can complete one full feature lifecycle on the
# GPU cluster (CPU-only path), with NO external egress:
#   1. Operator preflight: CRD + controller present  (else SKIP 77).
#   2. Create the FIRST FeatureStore CR -> operator reconciles to status.phase=Ready.
#      (operator runs `feast apply` on init against the scaffolded demo repo.)
#   3. Self-contained online-read Job using the SAME feature-server image the operator
#      deploys: synthesize a tiny data source in-cluster -> feast apply ->
#      feast materialize-incremental -> store.get_online_features() -> assert conv_rate.
#
# The data source is generated in-pod with pandas (bundled in the image); all stores are
# local (file registry, file offline, sqlite online), so the read needs no cross-pod
# networking and no PyPI/docker.io/HF access. The Job asserts driver_id=1001 reads back
# conv_rate=0.42, so a green Job == a verified online read.
#
# Exit codes: 0 pass / 1 fail / 77 skip (operator/image/CRD missing).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

CTX="${GPU_CONTEXT}"
NS="${FEAST_E2E_NS:-feast-e2e}"
OP_NS="${FEAST_OPERATOR_NS:-feast-operator-system}"
ASSETS="${E2E_ROOT}/../docs/en/feast/assets/first-cycle-e2e"
kc() { kubectl --context "${CTX}" "$@"; }

# ---- preflight (skip, don't fail, when the platform piece is absent) ----------
if ! kc get crd featurestores.feast.dev >/dev/null 2>&1; then
  log "C13: CRD featurestores.feast.dev missing — operator not installed; SKIP"
  exit 77
fi
if ! kc -n "${OP_NS}" get deploy feast-operator-controller-manager >/dev/null 2>&1; then
  log "C13: feast operator controller not found in ns/${OP_NS}; SKIP"
  log "C13: install it with: kubectl apply -f ${ASSETS}/operator-install.yaml"
  exit 77
fi
OP_READY="$(kc -n "${OP_NS}" get deploy feast-operator-controller-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [ "${OP_READY:-0}" -lt 1 ] 2>/dev/null; then
  log "C13: feast operator controller present but not Ready (readyReplicas=${OP_READY:-0}); SKIP"
  exit 77
fi
# Resolve the feature-server image the operator actually uses, so the smoke pins the
# exact same (cluster-pullable) image instead of a hard-coded one.
FEAST_IMAGE="$(kc -n "${OP_NS}" get deploy feast-operator-controller-manager \
  -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="RELATED_IMAGE_FEATURE_SERVER")]}{.value}{end}' 2>/dev/null || true)"
[ -z "${FEAST_IMAGE}" ] && FEAST_IMAGE="build-harbor.alauda.cn/mlops/feast/feature-server:0.63.0"
log "C13: operator ready; feature-server image=${FEAST_IMAGE}"

cleanup() { kc delete ns "${NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ---- 1. fresh namespace + first FeatureStore CR -------------------------------
kc create ns "${NS}" >/dev/null 2>&1 || true
log "C13: applying FeatureStore CR to ns/${NS}"
kc apply -f "${ASSETS}/featurestore.yaml" >/dev/null

log "C13: waiting for FeatureStore phase=Ready (<=10m)"
phase="$(wait_for_status kc featurestore feast-e2e "${NS}" '{.status.phase}' Ready Failed 600)"
if [ "${phase}" != "Ready" ]; then
  log "C13: FeatureStore did not reach Ready (phase=${phase}); conditions:"
  kc get featurestore feast-e2e -n "${NS}" -o jsonpath='{range .status.conditions[*]}{.type}={.status}|{.message}{"\n"}{end}' || true
  exit 1
fi
log "C13: FeatureStore Ready"

# ---- 2. self-contained online-read Job ---------------------------------------
log "C13: applying online-read Job (image pinned to operator's feature-server)"
sed "s#image: build-harbor.alauda.cn/mlops/feast/feature-server:0.63.0#image: ${FEAST_IMAGE}#" \
  "${ASSETS}/online-features-job.yaml" | kc apply -f - >/dev/null

log "C13: waiting for online-read Job to finish (<=10m)"
deadline=$((SECONDS + 600)); jobstate=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  s="$(kc get job feast-online-read -n "${NS}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  f="$(kc get job feast-online-read -n "${NS}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  [ "${s:-0}" = "1" ] && { jobstate="succeeded"; break; }
  [ "${f:-0}" = "1" ] && { jobstate="failed"; break; }
  sleep 10
done

log "C13: ===== online-read Job logs ====="
kc logs job/feast-online-read -n "${NS}" --tail=80 || true
log "C13: ===== end logs ====="

if [ "${jobstate}" != "succeeded" ]; then
  log "C13: online-read Job did not succeed (state=${jobstate:-timeout})"
  exit 1
fi
if ! kc logs job/feast-online-read -n "${NS}" 2>/dev/null | grep -q "SMOKE_OK"; then
  log "C13: Job succeeded but SMOKE_OK marker missing"
  exit 1
fi
log "C13: PASS — FeatureStore Ready and online read returned the expected conv_rate"
exit 0
