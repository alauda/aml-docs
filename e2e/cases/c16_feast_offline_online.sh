#!/usr/bin/env bash
# C16: SparkApplication + S3 Parquet -> Feast historical features -> Redis -> KServe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib.sh"
ASSET_DIR="${FEAST_ASSET_DIR:-$HERE/../../docs/en/train/guides/assets/feast-offline-to-online-inference}"
test -f "$ASSET_DIR/batch.py"
test -f "$ASSET_DIR/server.py"

require_env FEAST_NAMESPACE "namespace for Feast e2e resources"
require_env FEAST_IMAGE "Feast model-server image from the cluster registry"
require_env FEAST_SPARK_IMAGE "Spark runtime with Feast Spark and Hadoop S3A support"

NS="$FEAST_NAMESPACE"
PROJECT="feast_demo"
RUN_ID="$(printf '%05x' $$)-$(date -u +%s)"
FS_NAME="feast-e2e-$RUN_ID"
MODEL_PVC="$FS_NAME-model"
RUNTIME="$FS_NAME-runtime"
ISVC="$FS_NAME-isvc"
SPARK_APP="$FS_NAME-spark"
SPARK_SA="$FS_NAME-spark"
CM="$FS_NAME-code"
S3_KEY="e2e/$FS_NAME/driver_stats"
# The e2e prefix is unique per run; object-store lifecycle policy owns expiry.
TMP="$(mktemp -d)"
PF=""

cleanup() {
  [ -n "$PF" ] && kill "$PF" 2>/dev/null || true
  if [ "$FEAST_KEEP_RESOURCES" != 1 ]; then
    for item in \
      "inferenceservice $ISVC" "servingruntime $RUNTIME" \
      "sparkapplication $SPARK_APP" "configmap $CM" "pvc $MODEL_PVC" \
      "featurestore $FS_NAME" "rolebinding $SPARK_SA" "role $SPARK_SA" \
      "serviceaccount $SPARK_SA"; do
      set -- $item
      feast_kc -n "$NS" delete "$1" "$2" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

feast_kc get crd featurestores.feast.dev >/dev/null 2>&1 || {
  log "Feast CRD missing; skipping"
  exit "$E2E_SKIP_RC"
}
feast_kc get crd sparkapplications.sparkoperator.k8s.io >/dev/null 2>&1 || {
  log "OLM Spark Operator CRD missing; skipping"
  exit "$E2E_SKIP_RC"
}
feast_kc get crd inferenceservices.serving.kserve.io >/dev/null 2>&1 || {
  log "KServe CRD missing; skipping"
  exit "$E2E_SKIP_RC"
}

feast_kc create namespace "$NS" --dry-run=client -o yaml | feast_kc apply -f - >/dev/null
feast_kc create namespace feast-operator-system --dry-run=client -o yaml | feast_kc apply -f - >/dev/null
for secret in "$FEAST_DATA_STORES_SECRET" "$FEAST_S3_CREDENTIALS_SECRET"; do
  feast_kc -n "$NS" get secret "$secret" >/dev/null 2>&1 || {
    log "required Secret $NS/$secret missing; skipping"
    exit "$E2E_SKIP_RC"
  }
done

cat <<YAML | feast_kc apply -f -
apiVersion: feast.dev/v1
kind: FeatureStore
metadata: {name: $FS_NAME, namespace: $NS}
spec:
  feastProject: $PROJECT
  services:
    onlineStore:
      persistence:
        store:
          type: redis
          secretRef: {name: $FEAST_DATA_STORES_SECRET}
    registry:
      local:
        persistence:
          store:
            type: sql
            secretRef: {name: $FEAST_DATA_STORES_SECRET}
        server: {}
YAML

deadline=$((SECONDS + 600))
phase=""
while [ "$SECONDS" -lt "$deadline" ]; do
  phase="$(feast_kc -n "$NS" get featurestore "$FS_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$phase" = Ready ] && break
  [ "$phase" = Failed ] && {
    feast_kc -n "$NS" get featurestore "$FS_NAME" -o yaml >&2
    exit 1
  }
  sleep 10
done
[ "$phase" = Ready ] || { log "FeatureStore did not become Ready"; exit 1; }

CLIENT="$(feast_kc -n "$NS" get featurestore "$FS_NAME" -o jsonpath='{.status.clientConfigMap}')"
ONLINE_TLS="feast-$FS_NAME-online-tls"
REGISTRY_TLS="feast-$FS_NAME-registry-tls"

feast_kc -n "$NS" create configmap "$CM" \
  --from-file=batch.py="$ASSET_DIR/batch.py" \
  --from-file=server.py="$ASSET_DIR/server.py" \
  --dry-run=client -o yaml | feast_kc apply -f - >/dev/null

cat <<YAML | feast_kc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata: {name: $SPARK_SA, namespace: $NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: $SPARK_SA, namespace: $NS}
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: $SPARK_SA, namespace: $NS}
subjects:
- {kind: ServiceAccount, name: $SPARK_SA, namespace: $NS}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: $SPARK_SA}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $MODEL_PVC, namespace: $NS}
spec:
$(yaml_storage_class 2 "$FEAST_STORAGE_CLASS")
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
YAML

cat <<YAML | feast_kc apply -f -
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata: {name: $SPARK_APP, namespace: $NS}
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: $FEAST_SPARK_IMAGE
  imagePullPolicy: IfNotPresent
  mainApplicationFile: local:///opt/feast-batch/batch.py
  sparkVersion: "$FEAST_SPARK_VERSION"
  timeToLiveSeconds: 3600
  restartPolicy: {type: Never}
  sparkConf: {spark.sql.session.timeZone: UTC}
  volumes:
  - {name: batch-code, configMap: {name: $CM}}
  - name: feast-client
    configMap:
      name: $CLIENT
      items: [{key: feature_store.yaml, path: feature_store.yaml}]
  - {name: model, persistentVolumeClaim: {claimName: $MODEL_PVC}}
  - {name: online-tls, secret: {secretName: $ONLINE_TLS}}
  - {name: registry-tls, secret: {secretName: $REGISTRY_TLS}}
  driver:
    cores: 1
    memory: 2g
    serviceAccount: $SPARK_SA
    env:
    - {name: FEAST_PROJECT, value: $PROJECT}
    - {name: S3_DATASET_KEY, value: $S3_KEY}
    envFrom: [{secretRef: {name: $FEAST_S3_CREDENTIALS_SECRET}}]
    volumeMounts:
    - {name: batch-code, mountPath: /opt/feast-batch, readOnly: true}
    - {name: feast-client, mountPath: /etc/feast, readOnly: true}
    - {name: model, mountPath: /mnt/models}
    - {name: online-tls, mountPath: /tls/online, readOnly: true}
    - {name: registry-tls, mountPath: /tls/registry, readOnly: true}
  executor:
    instances: 2
    cores: 1
    memory: 1g
    envFrom: [{secretRef: {name: $FEAST_S3_CREDENTIALS_SECRET}}]
YAML

deadline=$((SECONDS + 1200))
state=""
while [ "$SECONDS" -lt "$deadline" ]; do
  state="$(feast_kc -n "$NS" get sparkapplication "$SPARK_APP" \
    -o jsonpath='{.status.applicationState.state}' 2>/dev/null || true)"
  case "$state" in
    COMPLETED|FAILED|FAILED_SUBMISSION|INVALIDATING|UNKNOWN) break ;;
  esac
  sleep 10
done
driver="$(feast_kc -n "$NS" get sparkapplication "$SPARK_APP" \
  -o jsonpath='{.status.driverInfo.podName}' 2>/dev/null || true)"
[ "$state" = COMPLETED ] || {
  log "SparkApplication ended in state ${state:-unset}"
  [ -n "$driver" ] && feast_kc -n "$NS" logs "$driver" --tail=300 >&2 || true
  exit 1
}
[ -n "$driver" ] && feast_kc -n "$NS" logs "$driver" --tail=100 || true

cat <<YAML | feast_kc apply -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata: {name: $RUNTIME, namespace: $NS}
spec:
  containers:
  - name: kserve-container
    image: $FEAST_IMAGE
    command: [python, /mnt/models/repo/server.py]
    ports: [{containerPort: 8080, name: http1, protocol: TCP}]
    env: [{name: MODEL_NAME, value: $ISVC}]
    volumeMounts:
    - {name: online-tls, mountPath: /tls/online, readOnly: true}
    - {name: registry-tls, mountPath: /tls/registry, readOnly: true}
  protocolVersions: [v2]
  supportedModelFormats: [{name: feast-numpy, version: "1"}]
  volumes:
  - {name: online-tls, secret: {secretName: $ONLINE_TLS}}
  - {name: registry-tls, secret: {secretName: $REGISTRY_TLS}}
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: $ISVC
  namespace: $NS
  annotations: {serving.kserve.io/deploymentMode: RawDeployment}
spec:
  predictor:
    model:
      modelFormat: {name: feast-numpy, version: "1"}
      protocolVersion: v2
      runtime: $RUNTIME
      storageUri: pvc://$MODEL_PVC
YAML

PREDICTOR_DEPLOY="$ISVC-predictor"
deadline=$((SECONDS + 1200))
available=""
while [ "$SECONDS" -lt "$deadline" ]; do
  available="$(feast_kc -n "$NS" get deployment "$PREDICTOR_DEPLOY" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  [ "${available:-0}" -ge 1 ] 2>/dev/null && break
  sleep 10
done
[ "${available:-0}" -ge 1 ] 2>/dev/null || {
  log "KServe predictor deployment did not become available"
  feast_kc -n "$NS" get inferenceservice "$ISVC" -o yaml >&2 || true
  exit 1
}

feast_kc -n "$NS" port-forward "service/$PREDICTOR_DEPLOY" 18080:80 >"$TMP/pf.log" 2>&1 &
PF=$!
for _ in $(seq 1 30); do
  curl -fsS http://127.0.0.1:18080/v2/health/ready >/dev/null 2>&1 && break
  sleep 2
done
response="$(curl -fsS -X POST "http://127.0.0.1:18080/v2/models/$ISVC/infer" \
  -H 'Content-Type: application/json' \
  -d '{"inputs":[{"name":"driver_id","shape":[2],"datatype":"INT64","data":[1,2]}]}')"
echo "$response"
echo "$response" | grep -q prediction
log "C16: SparkApplication S3 offline-to-Redis online inference passed"
