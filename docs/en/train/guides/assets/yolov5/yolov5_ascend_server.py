import os
from functools import lru_cache

import numpy as np
import torch
import torch_npu  # Registers the "npu" device with PyTorch.
from fastapi import FastAPI, HTTPException


MODEL_NAME = os.environ.get("MODEL_NAME", "yolov5-coco128")
MODEL_PATH = os.environ.get("MODEL_PATH", "/mnt/models/1/model.pt")
DEVICE = os.environ.get("NPU_DEVICE", "npu:0")
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
    if not isinstance(shape, list) or data is None:
        raise HTTPException(status_code=400, detail="images must include shape and data")

    values = np.asarray(data, dtype=np.float32)
    if values.size != int(np.prod(shape)):
        raise HTTPException(status_code=400, detail="images data does not match shape")

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
