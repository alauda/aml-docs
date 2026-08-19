#!/usr/bin/env bash
# C16: SparkApplication + S3 Parquet -> Feast historical features -> Redis -> KServe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib.sh"

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

cat >"$TMP/batch.py" <<'PY'
import copy
import json
import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlparse

import numpy as np
import pandas as pd
import yaml
from feast import FeatureStore
from pyspark.sql import SparkSession, functions as F

project = os.environ["FEAST_PROJECT"]
bucket = os.environ["S3_BUCKET"]
dataset_key = os.environ["S3_DATASET_KEY"].strip("/")
dataset_uri = f"s3a://{bucket}/{dataset_key}"
region = os.environ["AWS_DEFAULT_REGION"]
repo = Path("/tmp/feast-repo")
model_repo = Path("/mnt/models/repo")
repo.mkdir(parents=True, exist_ok=True)
model_repo.mkdir(parents=True, exist_ok=True)

spark = SparkSession.builder.appName("feast-offline-online-e2e").getOrCreate()
endpoint = urlparse(os.environ["S3_ENDPOINT_URL"])
hadoop = spark.sparkContext._jsc.hadoopConfiguration()
hadoop.set("fs.s3a.endpoint", endpoint.netloc or endpoint.path)
hadoop.set("fs.s3a.endpoint.region", region)
hadoop.set("fs.s3a.path.style.access", "true")
hadoop.set("fs.s3a.connection.ssl.enabled", str(endpoint.scheme == "https").lower())
hadoop.set("fs.s3a.access.key", os.environ["AWS_ACCESS_KEY_ID"])
hadoop.set("fs.s3a.secret.key", os.environ["AWS_SECRET_ACCESS_KEY"])

events = (
    spark.range(240)
    .withColumn("driver_id", (F.col("id") % 12 + 1).cast("long"))
    .withColumn("event_timestamp", F.timestamp_seconds(F.lit(1767225600) + F.col("id") * 3600))
    .withColumn("created", F.col("event_timestamp") + F.expr("INTERVAL 1 MINUTE"))
    .withColumn("conv_rate", (F.lit(0.25) + F.lit(0.55) * F.rand(7)).cast("float"))
    .withColumn("acc_rate", (F.lit(0.50) + F.lit(0.45) * F.rand(11)).cast("float"))
    .withColumn("avg_daily_trips", F.floor(F.lit(2) + F.lit(18) * F.rand(13)).cast("long"))
    .withColumn(
        "label",
        ((F.col("conv_rate") * 2 + F.col("acc_rate") + F.col("avg_daily_trips") / 20) > 1.8).cast("long"),
    )
    .drop("id")
)
events.repartition(4, "driver_id").write.mode("overwrite").partitionBy("driver_id").parquet(dataset_uri)

client_config = yaml.safe_load(Path("/etc/feast/feature_store.yaml").read_text())
batch_config = copy.deepcopy(client_config)
batch_config["offline_store"] = {
    "type": "spark",
    "spark_conf": {
        "spark.sql.session.timeZone": "UTC",
        "spark.hadoop.fs.s3a.endpoint": endpoint.netloc or endpoint.path,
        "spark.hadoop.fs.s3a.endpoint.region": region,
        "spark.hadoop.fs.s3a.path.style.access": "true",
        "spark.hadoop.fs.s3a.connection.ssl.enabled": str(endpoint.scheme == "https").lower(),
    },
}
(repo / "feature_store.yaml").write_text(yaml.safe_dump(batch_config, sort_keys=False))
(repo / "features.py").write_text(f'''from datetime import timedelta
from feast import Entity, FeatureService, FeatureView, Field
from feast.infra.offline_stores.contrib.spark_offline_store.spark_source import SparkSource
from feast.types import Float32, Int64
from feast.value_type import ValueType

driver = Entity(name="driver", join_keys=["driver_id"], value_type=ValueType.INT64)
source = SparkSource(
    name="driver_stats_source",
    path="{dataset_uri}",
    file_format="parquet",
    timestamp_field="event_timestamp",
    created_timestamp_column="created",
)
view = FeatureView(
    name="driver_hourly_stats",
    entities=[driver],
    ttl=timedelta(days=365),
    schema=[
        Field(name="conv_rate", dtype=Float32),
        Field(name="acc_rate", dtype=Float32),
        Field(name="avg_daily_trips", dtype=Int64),
    ],
    online=True,
    source=source,
)
driver_activity_v1 = FeatureService(name="driver_activity_v1", features=[view])
''')

subprocess.run(["feast", "--chdir", str(repo), "apply"], check=True)
store = FeatureStore(repo_path=str(repo))
entity_df = events.select("driver_id", "event_timestamp", "label").toPandas()
training = store.get_historical_features(
    entity_df=entity_df,
    features=[
        "driver_hourly_stats:conv_rate",
        "driver_hourly_stats:acc_rate",
        "driver_hourly_stats:avg_daily_trips",
    ],
).to_df().dropna()
columns = ["conv_rate", "acc_rate", "avg_daily_trips"]
x = training[columns].to_numpy(dtype="float64")
y = training["label"].to_numpy(dtype="float64")
weights = np.linalg.pinv(np.column_stack([np.ones(len(x)), x])) @ y
np.savez("/mnt/models/model.npz", weights=weights, feature_columns=np.array(columns))

end_date = events.agg(F.max("event_timestamp")).first()[0] + pd.Timedelta(hours=1)
store.materialize_incremental(end_date)
online = store.get_online_features(
    features=store.get_feature_service("driver_activity_v1"),
    entity_rows=[{"driver_id": 1}, {"driver_id": 2}],
).to_df()
if len(online) != 2 or online[columns].isna().any().any():
    raise RuntimeError(f"online feature verification failed: {online}")

serving_config = copy.deepcopy(client_config)
serving_config.pop("offline_store", None)
(model_repo / "feature_store.yaml").write_text(yaml.safe_dump(serving_config, sort_keys=False))
shutil.copy("/opt/feast-batch/server.py", model_repo / "server.py")
print(json.dumps({"historical_rows": len(training), "online_rows": len(online)}))

if os.environ.get("CLEANUP_S3") == "true":
    jvm = spark.sparkContext._jvm
    filesystem = jvm.org.apache.hadoop.fs.FileSystem.get(jvm.java.net.URI.create(dataset_uri), hadoop)
    filesystem.delete(jvm.org.apache.hadoop.fs.Path(dataset_uri), True)
spark.stop()
PY

cat >"$TMP/server.py" <<'PY'
import os
import numpy as np
import uvicorn
from fastapi import Body, FastAPI
from feast import FeatureStore

name = os.getenv("MODEL_NAME", "feast-online-model")
weights = np.load("/mnt/models/model.npz")["weights"]
store = FeatureStore(repo_path="/mnt/models/repo")
service = store.get_feature_service("driver_activity_v1")
app = FastAPI()

@app.get("/v2/health/ready")
@app.get("/v2/health/live")
def health():
    return {"ready": True}

@app.get("/v2/models/{model_name}")
@app.get("/v2/models/{model_name}/ready")
def ready(model_name):
    return {"name": model_name, "ready": model_name == name}

@app.post("/v2/models/{model_name}/infer")
def infer(model_name, payload: dict = Body(...)):
    ids = next(item for item in payload["inputs"] if item["name"] == "driver_id")["data"]
    values = store.get_online_features(
        features=service,
        entity_rows=[{"driver_id": int(value)} for value in ids],
    ).to_dict()
    def column(column_name):
        if column_name in values:
            return values[column_name]
        return values[next(key for key in values if key.endswith("__" + column_name))]
    matrix = np.column_stack([
        np.ones(len(ids)), column("conv_rate"), column("acc_rate"), column("avg_daily_trips")
    ])
    predictions = (matrix @ weights).astype("float32").tolist()
    return {
        "model_name": model_name,
        "outputs": [{"name": "prediction", "shape": [len(ids)], "datatype": "FP32", "data": predictions}],
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
PY

feast_kc -n "$NS" create configmap "$CM" \
  --from-file=batch.py="$TMP/batch.py" --from-file=server.py="$TMP/server.py" \
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
    - {name: CLEANUP_S3, value: "true"}
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
