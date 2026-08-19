#!/usr/bin/env bash
# C16: Feast Parquet -> historical features -> NumPy model -> online KServe prediction.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib.sh"
require_env FEAST_NAMESPACE "namespace for Feast e2e resources"
NS="$FEAST_NAMESPACE"
PROJECT="feast_demo"
RUN_ID="$(printf '%05x' $$)-$(date -u +%s)"
FS_NAME="feast-e2e-$RUN_ID"
MODEL_PVC="$FS_NAME-model"
RUNTIME="$FS_NAME-runtime"
ISVC="$FS_NAME-isvc"
JOB="$FS_NAME-job"
CM="$FS_NAME-runner"
IMAGE="$FEAST_IMAGE"; [ -n "$IMAGE" ] || IMAGE=build-harbor.alauda.cn/mlops/feast/feature-server:0.61.0
TMP="$(mktemp -d)"
PF=""
cleanup() {
  [ -n "$PF" ] && kill "$PF" 2>/dev/null || true
  if [ "$FEAST_KEEP_RESOURCES" != 1 ]; then
    for item in "inferenceservice $ISVC" "servingruntime $RUNTIME" "job $JOB" "configmap $CM" "pvc $MODEL_PVC" "featurestore $FS_NAME"; do
      set -- $item
      feast_kc -n "$NS" delete "$1" "$2" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
feast_kc get crd featurestores.feast.dev >/dev/null 2>&1 || { log "Feast CRD missing; skipping"; exit "$E2E_SKIP_RC"; }
feast_kc get crd inferenceservices.serving.kserve.io >/dev/null 2>&1 || { log "KServe CRD missing; skipping"; exit "$E2E_SKIP_RC"; }
feast_kc create namespace "$NS" --dry-run=client -o yaml | feast_kc apply -f - >/dev/null
feast_kc create namespace feast-operator-system --dry-run=client -o yaml | feast_kc apply -f - >/dev/null
cat <<YAML | feast_kc apply -f -
apiVersion: feast.dev/v1
kind: FeatureStore
metadata: {name: $FS_NAME, namespace: $NS}
spec:
  feastProject: $PROJECT
  services:
    registry: {local: {server: {}}}
    ui: {}
YAML
deadline=$((SECONDS + 600))
phase=""
while [ "$SECONDS" -lt "$deadline" ]; do
  phase="$(feast_kc -n "$NS" get featurestore "$FS_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$phase" = Ready ] && break
  [ "$phase" = Failed ] && { feast_kc -n "$NS" get featurestore "$FS_NAME" -o yaml >&2; exit 1; }
  sleep 10
done
[ "$phase" = Ready ] || { log "FeatureStore did not become Ready"; exit 1; }
CLIENT="$(feast_kc -n "$NS" get featurestore "$FS_NAME" -o jsonpath='{.status.clientConfigMap}')"
ONLINE_TLS="feast-$FS_NAME-online-tls"
REGISTRY_TLS="feast-$FS_NAME-registry-tls"

cat >"$TMP/features.py" <<'PY'
from datetime import timedelta
from feast import Entity, FeatureService, FeatureView, Field, FileSource
from feast.data_format import ParquetFormat
from feast.types import Float32, Int64
from feast.value_type import ValueType

driver = Entity(name="driver", join_keys=["driver_id"], value_type=ValueType.INT64)
source = FileSource(name="driver_stats_source", path="data/driver_stats.parquet",
                    file_format=ParquetFormat(), timestamp_field="event_timestamp",
                    created_timestamp_column="created")
view = FeatureView(name="driver_hourly_stats", entities=[driver], ttl=timedelta(days=365),
                   schema=[Field(name="conv_rate", dtype=Float32), Field(name="acc_rate", dtype=Float32),
                           Field(name="avg_daily_trips", dtype=Int64)], online=True, source=source)
driver_activity_v1 = FeatureService(name="driver_activity_v1", features=[view])
PY

# The remote online-store client intentionally has a no-op infrastructure update
# in Feast 0.61. Run apply once in the operand's local repository so its SQLite
# table exists before a remote materialize call writes rows to the online server.
online_pod=""
for _ in $(seq 1 60); do
  online_pod="$(feast_kc -n "$NS" get pods -l "feast.dev/name=$FS_NAME" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "$online_pod" ] && break
  sleep 5
done
[ -n "$online_pod" ] || { log "Feast online pod did not appear"; exit 1; }
feast_kc -n "$NS" wait --for=condition=Ready "pod/$online_pod" --timeout=300s >/dev/null
feast_kc -n "$NS" cp "$TMP/features.py" \
  "$NS/$online_pod:/feast-data/$PROJECT/feature_repo/feature_definitions.py" -c online
feast_kc -n "$NS" exec "$online_pod" -c online -- \
  bash -c "cd /feast-data/$PROJECT/feature_repo && feast apply"

cat >"$TMP/run.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
R=/mnt/models/repo
mkdir -p "$R/data"
cp /etc/feast/feature_store.yaml "$R/feature_store.yaml"
cp /runner/features.py "$R/features.py"
python - <<'PY'
import numpy as np, pandas as pd
rng=np.random.default_rng(7); n=240
df=pd.DataFrame({"driver_id":(np.arange(n)%12+1).astype("int64"),
 "event_timestamp":pd.date_range("2026-01-01",periods=n,freq="h",tz="UTC")})
df["created"]=df.event_timestamp+pd.to_timedelta(1,unit="m")
df["conv_rate"]=(.25+.55*rng.random(n)).astype("float32")
df["acc_rate"]=(.50+.45*rng.random(n)).astype("float32")
df["avg_daily_trips"]=rng.integers(2,20,size=n).astype("int64")
df["label"]=((df.conv_rate*2+df.acc_rate+df.avg_daily_trips/20)>1.8).astype("int64")
df.to_parquet("/mnt/models/repo/data/driver_stats.parquet",index=False)
PY
feast --chdir "$R" apply
python - <<'PY'
import numpy as np, pandas as pd
from feast import FeatureStore
r="/mnt/models/repo"; s=FeatureStore(repo_path=r); raw=pd.read_parquet(r+"/data/driver_stats.parquet")
t=s.get_historical_features(entity_df=raw[["driver_id","event_timestamp","label"]],
 features=["driver_hourly_stats:conv_rate","driver_hourly_stats:acc_rate",
           "driver_hourly_stats:avg_daily_trips"]).to_df().dropna()
x=t[["conv_rate","acc_rate","avg_daily_trips"]].to_numpy(float); y=t.label.to_numpy(float)
w=np.linalg.pinv(np.column_stack([np.ones(len(x)),x]))@y
np.savez("/mnt/models/model.npz",weights=w)
s.materialize_incremental(raw.event_timestamp.max().to_pydatetime()+pd.Timedelta(hours=1))
print("historical_rows",len(t),"weights",w.tolist())
PY
cp "$R/feature_store.yaml" /mnt/models/feature_store.yaml
cp "$R/features.py" /mnt/models/features.py
cp /runner/server.py /mnt/models/server.py
RUN
cat >"$TMP/server.py" <<'PY'
import os, numpy as np, uvicorn
from fastapi import Body, FastAPI
from feast import FeatureStore
name=os.getenv("MODEL_NAME","feast-online-model")
w=np.load("/mnt/models/model.npz")["weights"]; s=FeatureStore(repo_path="/mnt/models")
fs=s.get_feature_service("driver_activity_v1"); app=FastAPI()
@app.get("/v2/health/ready")
@app.get("/v2/health/live")
def health(): return {"ready":True}
@app.get("/v2/models/{model_name}")
@app.get("/v2/models/{model_name}/ready")
def ready(model_name): return {"name":model_name,"ready":model_name==name}
@app.post("/v2/models/{model_name}/infer")
def infer(model_name, payload: dict = Body(...)):
 ids=next(x for x in payload["inputs"] if x["name"]=="driver_id")["data"]
 values=s.get_online_features(features=fs,entity_rows=[{"driver_id":int(x)} for x in ids]).to_dict()
 def col(n):
  return values[n] if n in values else values[next(k for k in values if k.endswith("__"+n))]
 x=np.column_stack([np.ones(len(ids)),col("conv_rate"),col("acc_rate"),col("avg_daily_trips")])
 return {"model_name":model_name,"outputs":[{"name":"prediction","shape":[len(ids)],"datatype":"FP32","data":(x@w).astype("float32").tolist()}]}
if __name__=="__main__": uvicorn.run(app,host="0.0.0.0",port=8080)
PY

cat <<YAML | feast_kc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $MODEL_PVC, namespace: $NS}
spec:
$(yaml_storage_class 2 "$FEAST_STORAGE_CLASS")
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
YAML
feast_kc -n "$NS" create configmap "$CM" --from-file=run.sh="$TMP/run.sh" \
  --from-file=features.py="$TMP/features.py" --from-file=server.py="$TMP/server.py" \
  --dry-run=client -o yaml | feast_kc apply -f - >/dev/null

cat <<YAML | feast_kc apply -f -
apiVersion: batch/v1
kind: Job
metadata: {name: $JOB, namespace: $NS}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000}
      volumes:
      - {name: model, persistentVolumeClaim: {claimName: $MODEL_PVC}}
      - name: client
        configMap: {name: $CLIENT, items: [{key: feature_store.yaml, path: feature_store.yaml}]}
      - {name: runner, configMap: {name: $CM, defaultMode: 0555}}
      - {name: online-tls, secret: {secretName: $ONLINE_TLS}}
      - {name: registry-tls, secret: {secretName: $REGISTRY_TLS}}
      containers:
      - name: runner
        image: $IMAGE
        command: [bash, /runner/run.sh]
        volumeMounts:
        - {name: model, mountPath: /mnt/models}
        - {name: client, mountPath: /etc/feast, readOnly: true}
        - {name: runner, mountPath: /runner, readOnly: true}
        - {name: online-tls, mountPath: /tls/online, readOnly: true}
        - {name: registry-tls, mountPath: /tls/registry, readOnly: true}
        resources: {requests: {cpu: 250m, memory: 512Mi}, limits: {cpu: "1", memory: 2Gi}}
YAML
feast_kc -n "$NS" wait --for=condition=complete job/$JOB --timeout=1200s || { feast_kc -n "$NS" logs job/$JOB --tail=300 || true; exit 1; }

cat <<YAML | feast_kc apply -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata: {name: $RUNTIME, namespace: $NS}
spec:
  containers:
  - name: kserve-container
    image: $IMAGE
    command: [python, /mnt/models/server.py]
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
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat: {name: feast-numpy, version: "1"}
      protocolVersion: v2
      runtime: $RUNTIME
      storageUri: pvc://$MODEL_PVC
YAML
PREDICTOR_DEPLOY="$ISVC-predictor"
deadline=$((SECONDS + 1200)); available=""
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
SVC="$ISVC-predictor"
feast_kc -n "$NS" get service "$SVC" >/dev/null
feast_kc -n "$NS" port-forward "service/$SVC" 18080:80 >"$TMP/pf.log" 2>&1 &
PF=$!
for _ in $(seq 1 30); do curl -fsS http://127.0.0.1:18080/v2/health/ready >/dev/null 2>&1 && break; sleep 2; done
response="$(curl -fsS -X POST "http://127.0.0.1:18080/v2/models/$ISVC/infer" -H 'Content-Type: application/json' -d '{"inputs":[{"name":"driver_id","shape":[2],"datatype":"INT64","data":[1,2]}]}')"
echo "$response"; echo "$response" | grep -q prediction
log "C16: Feast offline-to-online inference demo passed"
