# A5 training smokes: M1 and C18

These two cases reproduce the training workloads in `950-npu-training-smoke-test-report.zh-CN.docx` (2026-10-29 evidence). They use ordinary Kubernetes Jobs; Kubeflow Trainer, external model repositories, PVCs, and downloaded model weights are not required.

| Case | Workload | Pass criteria |
| --- | --- | --- |
| M1 | One Pod requesting and limiting `huawei.com/npu: "1"`; runtime LLaMA Factory installation, a local tiny Qwen2 model and synthetic SFT dataset | Two LoRA optimizer steps, finite logged loss, saved adapter configuration and nonempty adapter weights |
| C18 | One Pod requesting and limiting `huawei.com/npu: "2"`; `torchrun --nnodes=1 --nproc-per-node=2` | Exactly two visible NPUs; one rank per logical device; HCCL DDP backward/optimizer step, synchronized parameters, all-reduce sum `3.0`, and barrier |

C18 checks distributed training plumbing with a tiny linear model. M1 performs real LoRA training on synthetic data. Neither case measures model quality or production training performance. Physical device IDs are allocated by the device plugin; the scripts do not select or stop host processes.

## Run only these cases

Prerequisites: Bash, Python 3 and kubectl locally; an existing namespace; an A5/Ascend 950DT node with the `huawei.com/npu` device plugin and enough free devices; pullable compatible arm64 training images. M1 needs outbound access to the Tsinghua PyPI mirror for its runtime dependencies. C18's image must include torch, torch_npu, torchrun, a passwd entry for UID 1001, and compatible CANN/HCCL libraries. Set the RuntimeClass only if required by your cluster.

```bash
export NPU_KUBECONFIG=/path/to/a5-kubeconfig.yaml
export NPU_CONTEXT=proxy-connect
export NPU_NAMESPACE=kubeflow-admin-cpaas-io
export E2E_NPU_NODE_SELECTOR_KEY=kubernetes.io/hostname
export E2E_NPU_NODE_SELECTOR_VALUE=10.226.72.95
# Optional, if required:
# export E2E_IMAGE_PULL_SECRET=harbor-a5-regcred
# export NPU_RUNTIME_CLASS=ascend
bash e2e/run_all.sh M1 C18
```

The default `M1_IMAGE` is `10.226.77.76:30002/library/vllm-ascend:v0.26.0rc2-a5`. The default `C18_IMAGE` is `10.226.77.76:30002/library/vllm-ascend:v0.23.0.post1-a5-openeuler-c8-c9-c11-20261029-arm64-c11fix2`. These are the images recorded in the report, not generic CANN images. Override either variable with an equivalent image mirrored into your cluster's reachable registry. Supply any required proxy environment to kubectl through your shell.

You can also run `bash e2e/cases/m1_llamafactory_lora_npu.sh` or `bash e2e/cases/c18_smoke_multi_npu_single_pod.sh` directly. M1 follows the reported root-user runtime installation; C18 runs as non-root UID 1001 without privilege escalation or added capabilities.

`A5_TIMEOUT` defaults to 1800 seconds for both the Job deadline and bounded polling. Every invocation uses a unique Job name. Completion requires a successful Job and the workload's explicit pass marker. Failure, timeout, or a missing marker returns nonzero; missing `NPU_NAMESPACE` returns the harness skip code (77 by default).

Evidence is stored under `e2e/logs/<job-name>/`: the submitted manifest, final Job and Pod JSON (including the device plugin's physical allocation annotations), Job description, and full training logs. Set `A5_OUTPUT_DIR` to change that parent directory. Jobs are deleted after evidence capture, including on failure; set `A5_KEEP_RESOURCES=1` to retain them for diagnosis. Workspace data and checkpoints are ephemeral and are validated inside the Job before cleanup.
