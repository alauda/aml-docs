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

endpoint = urlparse(os.environ["S3_ENDPOINT_URL"])
endpoint_host = endpoint.netloc or endpoint.path
ssl_enabled = str(endpoint.scheme == "https").lower()
spark = (
    SparkSession.builder.appName("feast-offline-batch")
    .config("spark.hadoop.fs.s3a.endpoint", endpoint_host)
    .config("spark.hadoop.fs.s3a.endpoint.region", region)
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", ssl_enabled)
    .getOrCreate()
)

n_rows = 240
events = (
    spark.range(n_rows)
    .withColumn("driver_id", (F.col("id") % 12 + 1).cast("long"))
    .withColumn(
        "event_timestamp",
        F.timestamp_seconds(F.lit(1767225600) + F.col("id") * 3600),
    )
    .withColumn("created", F.col("event_timestamp") + F.expr("INTERVAL 1 MINUTE"))
    .withColumn("conv_rate", (F.lit(0.25) + F.lit(0.55) * F.rand(7)).cast("float"))
    .withColumn("acc_rate", (F.lit(0.50) + F.lit(0.45) * F.rand(11)).cast("float"))
    .withColumn(
        "avg_daily_trips",
        F.floor(F.lit(2) + F.lit(18) * F.rand(13)).cast("long"),
    )
    .withColumn(
        "label",
        (
            (
                F.col("conv_rate") * 2
                + F.col("acc_rate")
                + F.col("avg_daily_trips") / 20
            )
            > 1.8
        ).cast("long"),
    )
    .drop("id")
)
events.repartition(4, "driver_id").write.mode("overwrite").partitionBy(
    "driver_id"
).parquet(dataset_uri)

client_config = yaml.safe_load(Path("/etc/feast/feature_store.yaml").read_text())
batch_config = copy.deepcopy(client_config)
batch_config["offline_store"] = {
    "type": "spark",
    "spark_conf": {
        "spark.sql.session.timeZone": "UTC",
        "spark.hadoop.fs.s3a.endpoint": endpoint_host,
        "spark.hadoop.fs.s3a.endpoint.region": region,
        "spark.hadoop.fs.s3a.path.style.access": "true",
        "spark.hadoop.fs.s3a.connection.ssl.enabled": ssl_enabled,
    },
}
(repo / "feature_store.yaml").write_text(
    yaml.safe_dump(batch_config, sort_keys=False)
)
(repo / "features.py").write_text(
    f'''from datetime import timedelta
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
'''
)

subprocess.run(["feast", "--chdir", str(repo), "apply"], check=True)
store = FeatureStore(repo_path=str(repo))
entity_df = events.select("driver_id", "event_timestamp", "label").toPandas()
training_df = store.get_historical_features(
    entity_df=entity_df,
    features=[
        "driver_hourly_stats:conv_rate",
        "driver_hourly_stats:acc_rate",
        "driver_hourly_stats:avg_daily_trips",
    ],
).to_df().dropna()
columns = ["conv_rate", "acc_rate", "avg_daily_trips"]
x = training_df[columns].to_numpy(dtype="float64")
y = training_df["label"].to_numpy(dtype="float64")
weights = np.linalg.pinv(np.column_stack([np.ones(len(x)), x])) @ y
np.savez(
    "/mnt/models/model.npz",
    weights=weights,
    feature_columns=np.array(columns),
)

end_date = events.agg(F.max("event_timestamp")).first()[0] + pd.Timedelta(hours=1)
store.materialize_incremental(end_date)
online = store.get_online_features(
    features=store.get_feature_service("driver_activity_v1"),
    entity_rows=[{"driver_id": 1}, {"driver_id": 2}],
).to_df()
if len(online) != 2 or online[columns].isna().any().any():
    raise RuntimeError(f"online feature verification failed: {online}")
online.to_json("/mnt/models/online-sample.json", orient="records")
serving_config = copy.deepcopy(client_config)
serving_config.pop("offline_store", None)
(model_repo / "feature_store.yaml").write_text(
    yaml.safe_dump(serving_config, sort_keys=False)
)
shutil.copy("/opt/feast-batch/server.py", model_repo / "server.py")
print(
    json.dumps(
        {
            "historical_rows": len(training_df),
            "dataset": dataset_uri,
            "online_rows": len(online),
        }
    )
)
spark.stop()
