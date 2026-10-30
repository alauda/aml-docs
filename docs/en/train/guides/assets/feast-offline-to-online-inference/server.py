import os

import numpy as np
import uvicorn
from fastapi import Body, FastAPI
from feast import FeatureStore

MODEL_NAME = os.getenv("MODEL_NAME", "feast-online-model")
weights = np.load("/mnt/models/model.npz")["weights"]
store = FeatureStore(repo_path="/mnt/models/repo")
feature_service = store.get_feature_service("driver_activity_v1")
app = FastAPI()


@app.get("/v2/health/live")
@app.get("/v2/health/ready")
def ready():
    return {"ready": True}


@app.get("/v2/models/{model_name}")
@app.get("/v2/models/{model_name}/ready")
def model_ready(model_name: str):
    return {"name": model_name, "ready": model_name == MODEL_NAME}


@app.post("/v2/models/{model_name}/infer")
def infer(model_name: str, payload: dict = Body(...)):
    ids = next(
        item for item in payload["inputs"] if item["name"] == "driver_id"
    )["data"]
    rows = [{"driver_id": int(driver_id)} for driver_id in ids]
    values = store.get_online_features(
        features=feature_service,
        entity_rows=rows,
    ).to_dict()

    def column(name):
        if name in values:
            return values[name]
        return values[next(key for key in values if key.endswith("__" + name))]

    x = np.column_stack(
        [
            np.ones(len(ids)),
            column("conv_rate"),
            column("acc_rate"),
            column("avg_daily_trips"),
        ]
    )
    prediction = (x @ weights).astype("float32")
    return {
        "model_name": model_name,
        "outputs": [
            {
                "name": "prediction",
                "shape": [len(ids)],
                "datatype": "FP32",
                "data": prediction.tolist(),
            }
        ],
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
