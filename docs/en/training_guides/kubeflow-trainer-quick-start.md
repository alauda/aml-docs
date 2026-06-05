---
weight: 20
---

# Kubeflow Trainer Quick Start

A minimal distributed PyTorch training setup on Alauda AI using Kubeflow Trainer v2: a custom runtime image, a `ClusterTrainingRuntime`, and an MNIST example notebook.

## Runtime image

Use the prebuilt image `alaudadockerhub/torch-distributed:v2.9.1-aml2`, or build your own from this `torch_distributed.Containerfile`:

```Dockerfile
FROM python:3.13-trixie
ARG USERNAME=appuser
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && apt-get install -y build-essential

RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -U pip && \
    pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu126 \
        "torch==2.9.1" "torchvision==0.24.1"

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

WORKDIR /workspace
RUN chown $USERNAME:$USER_GID /workspace
```

## ClusterTrainingRuntime

Apply this `kf-torch-distributed.yaml` as cluster admin. The pod spec is tightened for Alauda AI's default PSA.

```yaml
apiVersion: trainer.kubeflow.org/v1alpha1
kind: ClusterTrainingRuntime
metadata:
  name: torch-distributed
  labels:
    trainer.kubeflow.org/framework: torch
spec:
  mlPolicy:
    numNodes: 1
    torch:
      numProcPerNode: auto
  template:
    spec:
      replicatedJobs:
        - name: node
          template:
            metadata:
              labels:
                trainer.kubeflow.org/trainjob-ancestor-step: trainer
            spec:
              template:
                spec:
                  securityContext:
                    runAsNonRoot: true
                    runAsUser: 1000
                    runAsGroup: 1000
                    fsGroup: 1000
                  volumes:
                    - name: dshm
                      emptyDir:
                        medium: Memory
                        sizeLimit: 2Gi
                    - name: workspace
                      emptyDir: {}
                  containers:
                    - name: node
                      image: alaudadockerhub/torch-distributed:v2.9.1-aml2
                      env:
                        - { name: TORCH_HOME,           value: /tmp/torch_cache }
                        - { name: TORCH_EXTENSIONS_DIR, value: /tmp/torch_extensions }
                        - { name: TRITON_CACHE_DIR,     value: /tmp/triton_cache }
                      volumeMounts:
                        - { name: workspace, mountPath: /workspace }
                        - { name: dshm,      mountPath: /dev/shm }
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities: { drop: [ALL] }
                        runAsNonRoot: true
                        seccompProfile: { type: RuntimeDefault }
```

## Run the example notebook

The notebook installs Python packages and downloads MNIST, so the workbench needs outbound network access.

Download [`kubeflow-trainer-mnist.ipynb`](https://github.com/alauda/aml-docs/tree/master/docs/en/training_guides/kubeflow-trainer-mnist.ipynb) and upload it to your workbench, then follow it to submit the `TrainJob`.

For background on Trainer v2 features, see the [upstream Kubeflow Trainer docs](https://www.kubeflow.org/docs/components/trainer/).
