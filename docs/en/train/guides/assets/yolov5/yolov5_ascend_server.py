import os
from functools import lru_cache

import numpy as np
import torch
import torch_npu  # Registers the "npu" device with PyTorch.
from fastapi import FastAPI, HTTPException


MODEL_NAME = os.environ.get("MODEL_NAME", "yolov5-coco128")
MODEL_PATH = os.environ.get("MODEL_PATH", "/mnt/models/1/model.pt")
DEVICE = os.environ.get("NPU_DEVICE", "npu:0")
MAX_BATCH_SIZE = int(os.environ.get("MAX_BATCH_SIZE", "8"))
INPUT_SHAPE = (3, 640, 640)
app = FastAPI()


@lru_cache(maxsize=1)
def model():
    if not torch_npu.npu.is_available():
        raise RuntimeError("No Ascend NPU is available to torch_npu")
    if not os.path.isfile(MODEL_PATH):
        raise RuntimeError(f"TorchScript model not found: {MODEL_PATH}")
    loaded = torch.jit.load(MODEL_PATH, map_location="cpu")
    loaded.to(DEVICE).eval()
    return loaded


@app.on_event("startup")
def load_model():
    model()


@app.get("/v2/health/live")
@app.get("/v2/health/ready")
@app.get("/v2/models/{model_name}/ready")
def ready(model_name: str | None = None):
    if model_name is not None and model_name != MODEL_NAME:
        raise HTTPException(status_code=404, detail="Unknown model")
    model()
    return {}


@app.post("/v2/models/{model_name}/infer")
def infer(model_name: str, request: dict):
    if model_name != MODEL_NAME:
        raise HTTPException(status_code=404, detail="Unknown model")

    inputs = request.get("inputs", [])
    image = next((item for item in inputs if item.get("name") == "images"), None)
    if image is None:
        raise HTTPException(status_code=400, detail="Missing FP32 input named images")
    if image.get("datatype") != "FP32":
        raise HTTPException(status_code=400, detail="images must use FP32 data")

    shape = image.get("shape")
    data = image.get("data")
    if not isinstance(shape, list) or not isinstance(data, list):
        raise HTTPException(status_code=400, detail="images must include shape and data")

    if (
        len(shape) != 4
        or any(not isinstance(dimension, int) or isinstance(dimension, bool) for dimension in shape)
        or not 1 <= shape[0] <= MAX_BATCH_SIZE
        or tuple(shape[1:]) != INPUT_SHAPE
    ):
        raise HTTPException(
            status_code=400,
            detail=f"images must have shape [batch, 3, 640, 640] with batch between 1 and {MAX_BATCH_SIZE}",
        )

    expected_values = int(np.prod(shape))
    if len(data) != expected_values:
        raise HTTPException(status_code=400, detail="images data does not match shape")

    try:
        values = np.asarray(data, dtype=np.float32)
    except (TypeError, ValueError) as error:
        raise HTTPException(status_code=400, detail="images data must contain FP32 values") from error

    tensor = torch.from_numpy(values.reshape(shape)).to(DEVICE)
    with torch.inference_mode():
        output = model()(tensor)
    if isinstance(output, (tuple, list)):
        output = output[0]
    output = output.detach().float().cpu().numpy()

    return {
        "model_name": MODEL_NAME,
        "model_version": "1",
        "outputs": [
            {
                "name": "output0",
                "datatype": "FP32",
                "shape": list(output.shape),
                "data": output.flatten().tolist(),
            }
        ],
    }
