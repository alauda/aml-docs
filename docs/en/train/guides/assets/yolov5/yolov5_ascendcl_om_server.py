from __future__ import annotations

import os
from functools import lru_cache
from threading import Lock

import acl
import numpy as np
from fastapi import FastAPI, HTTPException


ACL_SUCCESS = 0
ACL_FLOAT = 0
ACL_MEM_MALLOC_NORMAL_ONLY = 2
ACL_MEMCPY_HOST_TO_DEVICE = 1
ACL_MEMCPY_DEVICE_TO_HOST = 2
ACL_MEMCPY_DEVICE_TO_DEVICE = 3
ACL_HOST = 1
MODEL_NAME = os.environ.get("MODEL_NAME", "yolov5-coco128")
MODEL_PATH = os.environ.get("MODEL_PATH", "/mnt/models/1/model.om")
DEVICE_ID = int(os.environ.get("ASCEND_DEVICE_ID", "0"))
INPUT_SHAPE = (1, 3, 640, 640)
app = FastAPI()


def check_acl(operation: str, result: int):
    if result != ACL_SUCCESS:
        raise RuntimeError(f"{operation} failed with error code {result}")


class AscendCLModel:
    def __init__(self, model_path: str, device_id: int):
        if not os.path.isfile(model_path):
            raise RuntimeError(f"CANN offline model not found: {model_path}")

        self.device_id = device_id
        self.context = None
        self.model_id = None
        self.model_desc = None
        self.input_dataset = None
        self.output_dataset = None
        self.input_buffer = None
        self.input_size = 0
        self.output_buffers = []
        self.lock = Lock()
        self.closed = False

        check_acl("acl.init", acl.init())
        check_acl("acl.rt.set_device", acl.rt.set_device(self.device_id))
        self.context, result = acl.rt.create_context(self.device_id)
        check_acl("acl.rt.create_context", result)
        self._activate()

        self.model_id, result = acl.mdl.load_from_file(model_path)
        check_acl("acl.mdl.load_from_file", result)
        self.model_desc = acl.mdl.create_desc()
        check_acl("acl.mdl.get_desc", acl.mdl.get_desc(self.model_desc, self.model_id))

        if acl.mdl.get_num_inputs(self.model_desc) != 1:
            raise RuntimeError("This sample requires an .om model with one input")
        if acl.mdl.get_num_outputs(self.model_desc) != 1:
            raise RuntimeError("This sample requires an .om model with one output")
        if acl.mdl.get_input_data_type(self.model_desc, 0) != ACL_FLOAT:
            raise RuntimeError("This sample requires an .om model with one FP32 input")
        if acl.mdl.get_output_data_type(self.model_desc, 0) != ACL_FLOAT:
            raise RuntimeError("This sample requires an .om model with one FP32 output")

        self.input_size = acl.mdl.get_input_size_by_index(self.model_desc, 0)
        expected_input_size = int(np.prod(INPUT_SHAPE)) * np.dtype(np.float32).itemsize
        if self.input_size != expected_input_size:
            raise RuntimeError(
                "The .om input size does not match the sample's fixed FP32 "
                f"input shape {list(INPUT_SHAPE)}"
            )
        self.input_dataset = acl.mdl.create_dataset()
        self.input_buffer, result = acl.rt.malloc(self.input_size, ACL_MEM_MALLOC_NORMAL_ONLY)
        check_acl("acl.rt.malloc input", result)
        input_data = acl.create_data_buffer(self.input_buffer, self.input_size)
        _, result = acl.mdl.add_dataset_buffer(self.input_dataset, input_data)
        check_acl("acl.mdl.add_dataset_buffer input", result)

        self.output_dataset = acl.mdl.create_dataset()
        output_size = acl.mdl.get_output_size_by_index(self.model_desc, 0)
        output_buffer, result = acl.rt.malloc(output_size, ACL_MEM_MALLOC_NORMAL_ONLY)
        check_acl("acl.rt.malloc output", result)
        output_data = acl.create_data_buffer(output_buffer, output_size)
        _, result = acl.mdl.add_dataset_buffer(self.output_dataset, output_data)
        check_acl("acl.mdl.add_dataset_buffer output", result)
        self.output_buffers.append((output_buffer, output_size))

        self.run_mode, result = acl.rt.get_run_mode()
        check_acl("acl.rt.get_run_mode", result)

    def _activate(self):
        check_acl("acl.rt.set_current_context", acl.rt.set_current_context(self.context))

    def infer(self, image: np.ndarray) -> np.ndarray:
        if image.shape != INPUT_SHAPE or image.dtype != np.float32:
            raise ValueError(f"images must be FP32 with shape {list(INPUT_SHAPE)}")
        image = np.ascontiguousarray(image)

        with self.lock:
            self._activate()
            copy_kind = ACL_MEMCPY_HOST_TO_DEVICE if self.run_mode == ACL_HOST else ACL_MEMCPY_DEVICE_TO_DEVICE
            source = acl.util.numpy_to_ptr(image)
            check_acl(
                "acl.rt.memcpy input",
                acl.rt.memcpy(self.input_buffer, self.input_size, source, image.nbytes, copy_kind),
            )
            check_acl("acl.mdl.execute", acl.mdl.execute(self.model_id, self.input_dataset, self.output_dataset))

            dims, result = acl.mdl.get_cur_output_dims(self.model_desc, 0)
            check_acl("acl.mdl.get_cur_output_dims", result)
            output_shape = tuple(dims["dims"])
            output = np.empty(output_shape, dtype=np.float32)
            output_size = output.nbytes
            output_buffer, allocated_size = self.output_buffers[0]
            if output_size > allocated_size:
                raise RuntimeError("The .om output is larger than its allocated output buffer")
            destination = acl.util.numpy_to_ptr(output)
            copy_kind = ACL_MEMCPY_DEVICE_TO_HOST if self.run_mode == ACL_HOST else ACL_MEMCPY_DEVICE_TO_DEVICE
            check_acl(
                "acl.rt.memcpy output",
                acl.rt.memcpy(destination, output_size, output_buffer, output_size, copy_kind),
            )
            return output

    def close(self):
        if self.closed:
            return
        self.closed = True
        if self.context is not None:
            self._activate()
        for dataset in (self.input_dataset, self.output_dataset):
            if dataset is None:
                continue
            for index in range(acl.mdl.get_dataset_num_buffers(dataset)):
                data = acl.mdl.get_dataset_buffer(dataset, index)
                if data is not None:
                    acl.destroy_data_buffer(data)
            acl.mdl.destroy_dataset(dataset)
        if self.input_buffer is not None:
            acl.rt.free(self.input_buffer)
        for buffer, _ in self.output_buffers:
            acl.rt.free(buffer)
        if self.model_id is not None:
            acl.mdl.unload(self.model_id)
        if self.model_desc is not None:
            acl.mdl.destroy_desc(self.model_desc)
        if self.context is not None:
            acl.rt.destroy_context(self.context)
        acl.rt.reset_device(self.device_id)
        acl.finalize()


@lru_cache(maxsize=1)
def model():
    return AscendCLModel(MODEL_PATH, DEVICE_ID)


@app.on_event("startup")
def load_model():
    model()


@app.on_event("shutdown")
def unload_model():
    if model.cache_info().currsize:
        model().close()
        model.cache_clear()


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
    if shape != list(INPUT_SHAPE) or not isinstance(data, list):
        raise HTTPException(status_code=400, detail=f"images must have shape {list(INPUT_SHAPE)}")
    if len(data) != int(np.prod(INPUT_SHAPE)):
        raise HTTPException(status_code=400, detail="images data does not match shape")

    try:
        values = np.asarray(data, dtype=np.float32).reshape(INPUT_SHAPE)
        output = model().infer(values)
    except (TypeError, ValueError) as error:
        raise HTTPException(status_code=400, detail="images data must contain FP32 values") from error
    except RuntimeError as error:
        raise HTTPException(status_code=500, detail="AscendCL inference failed") from error

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
