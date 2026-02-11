---
weight: 30
---

# Kubeflow Trainer Quick Start

## Background

Kubeflow Trainer v2 is a component of Kubeflow that simplifies the process of running distributed machine learning training jobs on Kubernetes. It provides a standardized way to define training runtimes and jobs, supporting various frameworks like PyTorch, Transformers, TensorFlow, and others. In Alauda AI, Kubeflow Trainer v2 integrates seamlessly with the platform's notebook environment, allowing users to submit and manage training jobs directly from their development workspace.

This quick start guide demonstrates how to set up a distributed PyTorch training environment using Kubeflow Trainer v2. You'll learn to build a custom runtime image, configure a ClusterTrainingRuntime, and run an example training job for MNIST classification. This setup enables efficient distributed training on GPU clusters, leveraging Alauda AI's resource management and security features.

## Prepare Runtime Image

Create a `torch_distributed.Containerfile` from below contents and build a image. Or you can use pre-built image `alaudadockerhub/torch-distributed:v2.9.1-aml2`.

```
FROM python:3.13-trixie
ARG USERNAME=appuser
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
RUN apt-get update && \
apt-get install -y build-essential

RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -U pip && \
pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu126 \
"torch==2.9.1" \
"torchvision==0.24.1"

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

WORKDIR /workspace
RUN chown $USERNAME:$USER_GID /workspace
```

## Prepare ClusterTrainingRuntime

Create a `kf-torch-distributed.yaml` file to add a `ClusterTrainingRuntime` configuration to start Distributed pytorch `TrainJob` on Alauda AI. Then run `kubectl apply -f kf-torch-distributed.yaml` as admin to create.

> **Note: the default `ClusterTrainingRuntime` was modified to fit Alauda AI's default security settings.**

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
                  - emptyDir:
                      medium: Memory
                      # Here you can adjust the size of the shared memory used
                      sizeLimit: 2Gi
                    name: dshm
                  # EmptyDir as workspace for training and share output model to the final step.
                  - name: workspace
                    emptyDir: {}
                  containers:
                    - name: node
                      # use image built in above step here or our pre-built image.
                      image: alaudadockerhub/torch-distributed:v2.9.1-aml2
                      env:
                      - name: TORCH_HOME
                        value: /tmp/torch_cache
                      - name: TORCH_EXTENSIONS_DIR
                        value: /tmp/torch_extensions
                      - name: TRITON_CACHE_DIR
                        value: /tmp/triton_cache
                      volumeMounts:
                        - name: workspace
                          mountPath: /workspace
                        - name: dshm
                          mountPath: /dev/shm
                      securityContext:
                        allowPrivilegeEscalation: false
                        capabilities:
                          drop:
                            - ALL
                        runAsNonRoot: true
                        seccompProfile:
                          type: RuntimeDefault
```

## Run the Example Notebook

> **Note: You need internet access to run below example notebook, since you need to install python packages, download datasets in this notebook.**

Download [kubeflow_trainer_mnist.ipynb](./kubeflow_trainer_mnist.ipynb) and drag drop the file into your notebook instance. Follow the guide in this notebook to start a `TrainJob` using pytorch.

For more informatoin about how to use **Kubeflow Trainer v2**, please refer to [Kubeflow Document](https://www.kubeflow.org/docs/components/trainer/)

## Conclusion

By following this quick start guide, you have successfully set up Kubeflow Trainer v2 in your Alauda AI environment and run a distributed PyTorch training job. This foundation allows you to scale your machine learning workloads efficiently across multiple nodes and GPUs.

Next steps:
- Experiment with different models and datasets by modifying the example notebook.
- Explore advanced features like custom metrics, hyperparameter tuning, and integration with MLflow for experiment tracking.
- Adapt the ClusterTrainingRuntime for other frameworks such as TensorFlow or custom training scripts.

For more detailed documentation and advanced configurations, refer to the [Kubeflow Trainer v2 documentation](https://www.kubeflow.org/docs/components/trainer/).
