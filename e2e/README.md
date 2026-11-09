# E2E scripts

Run cases from the repository root with `bash e2e/run_all.sh C19 C18`, or run a case script directly. With no case IDs, the runner selects all registered cases. It writes runner logs to `e2e/logs` and distinguishes PASS, FAIL, and SKIP (exit 77 by default).

Existing cases use their documented GPU, NPU, Feast, or Ray Data environments through `e2e/lib.sh`. The device switch below applies to **C18 and C19**; it does not convert the other cases to a different backend.

## C18 and C19

| Case | Workload | Success checks |
| --- | --- | --- |
| C18 | One Pod, two torchrun processes, one device per rank for GPU/NPU | DDP backward and optimizer update, finite loss and gradients, synchronized parameters, all-reduce sum `3.0`, and barrier |
| C19 | One Pod, one device, tiny locally generated Qwen2 model and synthetic SFT dataset | Two LLaMA Factory LoRA optimizer steps, finite logged loss, saved adapter configuration and nonempty weights |

These are training smoke tests, not model-quality or performance benchmarks. They use ordinary Kubernetes Jobs and ephemeral storage, without external model downloads, PVCs, or a Kubeflow Trainer installation. C19 installs LLaMA Factory 0.9.4 and compatible Transformers dependencies at runtime and needs package-index access.

## Select a device

`TRAINING_DEVICE` defaults to `gpu`. The device determines the PyTorch device, distributed backend, and Kubernetes extended resource together:

| Setting | PyTorch device | C18 backend | Resource requests and limits |
| --- | --- | --- | --- |
| `gpu` (default) | CUDA | NCCL | `nvidia.com/gpu`: C18=`"2"`, C19=`"1"` |
| `npu` | Ascend NPU (`torch_npu`) | HCCL | `huawei.com/npu`: C18=`"2"`, C19=`"1"` |
| `cpu` | CPU | Gloo | No accelerator resource; C18 still runs two processes |

The cluster needs a matching device plugin and enough available devices for GPU/NPU execution. A backend unavailable in the image fails the case instead of falling back to CPU. A custom resource name changes scheduling only; it does not add support for another PyTorch backend.

### GPU (default)

```bash
export GPU_KUBECONFIG=/path/to/kubeconfig
export GPU_CONTEXT=my-gpu-context
export GPU_NAMESPACE=training-tests
bash e2e/run_all.sh C19 C18
```

C19 defaults to `docker.io/alaudadockerhub/llamafactory0.9-cu126-amd64:v0.1.0`; C18 defaults to `docker.io/alaudadockerhub/torch2.6-cu126-amd64:v0.1.0`. These defaults target amd64 CUDA environments. Set `C19_IMAGE` and `C18_IMAGE` to compatible images for your architecture, driver, and reachable registry. `GPU_DH_MIRROR` rewrites `docker.io/` references for these cases as in the other GPU cases.

### NPU

```bash
export TRAINING_DEVICE=npu
export NPU_KUBECONFIG=/path/to/kubeconfig
export NPU_CONTEXT=my-npu-context
export NPU_NAMESPACE=training-tests
export C19_IMAGE=my-registry.example/training/llamafactory:ascend
export C18_IMAGE=my-registry.example/training/pytorch:ascend
# If required by the cluster:
# export TRAINING_RUNTIME_CLASS=ascend
bash e2e/run_all.sh C19 C18
```

NPU images must be supplied explicitly. Match the device generation, CPU architecture, CANN/HCCL libraries, torch, and torch_npu versions. C18 also needs torchrun and a passwd entry for UID 1001; it runs without privilege escalation or added capabilities. C19 runs as the image's default user, which must be able to install packages under `/workspace/runtime-py`. The payload sources available Ascend environment scripts only for NPU execution. `NPU_DH_MIRROR` rewrites any `docker.io/` image references.

### CPU

```bash
export TRAINING_DEVICE=cpu
export TRAINING_KUBECONFIG=/path/to/kubeconfig
export TRAINING_CONTEXT=my-cpu-context
export TRAINING_NAMESPACE=training-tests
# Override C18_IMAGE/C19_IMAGE if the CUDA defaults are not suitable for this host.
bash e2e/run_all.sh C19 C18
```

C19 uses CPU training without mixed precision. GPU execution enables BF16 only when supported by the GPU; NPU execution uses BF16.

## Configuration for C18/C19

| Variable | Purpose |
| --- | --- |
| `TRAINING_NAMESPACE`, `TRAINING_CONTEXT`, `TRAINING_KUBECONFIG` | Override the selected GPU/NPU target. CPU uses these variables directly. Namespace must already exist. |
| `C18_IMAGE`, `C19_IMAGE` | Override each case's image; `TRAINING_IMAGE` is a shared fallback. |
| `TRAINING_RESOURCE_NAME` | Override the GPU/NPU extended resource key. Counts remain two for C18 and one for C19. Ignored for CPU. |
| `TRAINING_NODE_SELECTOR_KEY`, `TRAINING_NODE_SELECTOR_VALUE` | Optional node label selector; no node is selected by default. Existing `E2E_GPU_NODE_SELECTOR_KEY/VALUE` or `E2E_NPU_NODE_SELECTOR_KEY/VALUE` are fallbacks for the selected device. |
| `TRAINING_RUNTIME_CLASS` | Optional RuntimeClass; `NPU_RUNTIME_CLASS` is a fallback for NPU. |
| `E2E_IMAGE_PULL_SECRET` | Existing pull secret in the target namespace. |
| `TRAINING_PIP_INDEX_URL` | C19 package index, default `https://pypi.org/simple`; for example `https://pypi.tuna.tsinghua.edu.cn/simple`. |
| `TRAINING_TIMEOUT` | Positive execution deadline in seconds, default 1800. |
| `TRAINING_OUTPUT_DIR` | Evidence parent directory, default `e2e/logs`. |
| `TRAINING_KEEP_RESOURCES=1` | Keep Jobs for debugging; default cleanup follows evidence capture, including on failure. |

`SKIP_GPU=1` and `SKIP_NPU=1` follow `TRAINING_DEVICE` for these two cases. Supply any required kubectl proxy settings in the invoking shell.

Each run creates a unique Job. The case requires both successful Job completion and the training payload's explicit pass marker. A failed Job, timeout, or missing marker returns nonzero. Missing namespace configuration, or a missing required NPU image, returns the harness skip code.

Evidence under `<output-dir>/<job-name>/` includes the submitted manifest, Job and Pod JSON, Job description, and complete training logs. Device-plugin allocation annotations are preserved in the Pod JSON. Checkpoints are validated inside the Job before its ephemeral storage is removed.
