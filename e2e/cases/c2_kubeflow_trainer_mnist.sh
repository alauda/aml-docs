#!/usr/bin/env bash
# C2 — exercises the `kubeflow-trainer-quick-start.md` runtime end to end.
# Differences from the published notebook:
#   - skips the Kubeflow SDK install / LocalProcessBackend probe (notebook cells 1–6
#     are workbench bootstrap; the runtime path is what we verify)
#   - replaces the FashionMNIST download with a synthetic tensor dataset, so the
#     case runs with no outbound network and no public dataset mirror
#   - the `train_fashion_mnist` body is reproduced verbatim apart from the dataset
#     substitution, so the doc's training-function snippet is still exercised
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "${HERE}/../lib.sh"

NS="${GPU_NAMESPACE}"

log "C2: applying ClusterTrainingRuntime torch-distributed (from kubeflow-trainer-quick-start.md)"
# Pulled directly out of docs/en/training_guides/kubeflow-trainer-quick-start.md.
# Image override: docker-mirrors.alauda.cn proxies docker.io but the lazy-cache
# returns EOF on the torch-distributed blobs (only torch2.6-* are cached). The
# alauda-local registry mirror has the image pre-pulled. Doc itself stays at
# the public alaudadockerhub/ name; only the test overrides for network reasons.
TORCH_DIST_IMAGE="${TORCH_DIST_IMAGE:-152-231-registry.alauda.cn:60070/mlops/torch-distributed:v2.9.1-aml2}"
cat <<'YAML' | sed "s@alaudadockerhub/torch-distributed:v2.9.1-aml2@${TORCH_DIST_IMAGE}@g" | retry_apply gpu_kc
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
YAML

# Encode the training function with a synthetic dataset substitute. We keep the
# notebook's exact distributed setup; only the data source changes.
TRAIN_PY=$(cat <<'PY'
import os
import torch
import torch.distributed as dist
import torch.nn.functional as F
from torch import nn
from torch.utils.data import DataLoader, DistributedSampler, TensorDataset


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 20, 5, 1)
        self.conv2 = nn.Conv2d(20, 50, 5, 1)
        self.fc1 = nn.Linear(4 * 4 * 50, 500)
        self.fc2 = nn.Linear(500, 10)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2, 2)
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2, 2)
        x = x.view(-1, 4 * 4 * 50)
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        return F.log_softmax(x, dim=1)


device_name, backend = ("cuda", "nccl") if torch.cuda.is_available() else ("cpu", "gloo")
print(f"Using Device: {device_name}, Backend: {backend}", flush=True)
# The doc's notebook runs under TrainerClient.train(), which wraps the function
# with torchrun and sets RANK/WORLD_SIZE/LOCAL_RANK/MASTER_*. The TrainJob
# `trainer.command` override bypasses that wrapper, so fill in single-node
# defaults from the Trainer v2 PET_* env vars before init_process_group.
os.environ.setdefault("MASTER_ADDR", "127.0.0.1")
os.environ.setdefault("MASTER_PORT", "29500")
os.environ.setdefault("WORLD_SIZE", os.environ.get("PET_NNODES", "1"))
os.environ.setdefault("RANK",       os.environ.get("PET_NODE_RANK", "0"))
os.environ.setdefault("LOCAL_RANK", "0")
local_rank = int(os.getenv("LOCAL_RANK", 0))
dist.init_process_group(backend=backend)
print(
    f"Distributed Training for WORLD_SIZE: {dist.get_world_size()}, "
    f"RANK: {dist.get_rank()}, LOCAL_RANK: {local_rank}",
    flush=True,
)

device = torch.device(f"{device_name}:{local_rank}" if device_name == "cuda" else "cpu")
model = Net().to(device)
model = nn.parallel.DistributedDataParallel(model)
optimizer = torch.optim.SGD(model.parameters(), lr=0.1, momentum=0.9)

# Synthetic Fashion-MNIST-shaped data so the case is reproducible without
# downloading the real dataset. Same shape (1x28x28) and label range as the
# original notebook so the model code is unchanged.
torch.manual_seed(0)
N = 1024
x = torch.rand(N, 1, 28, 28)
y = torch.randint(0, 10, (N,))
dataset = TensorDataset(x, y)
loader = DataLoader(dataset, batch_size=64, sampler=DistributedSampler(dataset))

dist.barrier()
for epoch in range(1, 2):
    model.train()
    for batch_idx, (inputs, labels) in enumerate(loader):
        inputs, labels = inputs.to(device), labels.to(device)
        outputs = model(inputs)
        loss = F.nll_loss(outputs, labels)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        if batch_idx % 4 == 0 and dist.get_rank() == 0:
            print(
                f"Train Epoch: {epoch} [{batch_idx * len(inputs)}/{len(loader.dataset)} "
                f"({100.0 * batch_idx / len(loader):.0f}%)]\tLoss: {loss.item():.6f}",
                flush=True,
            )

dist.barrier()
if dist.get_rank() == 0:
    print("Training is finished", flush=True)
dist.destroy_process_group()
PY
)

log "C2: submitting TrainJob using torch-distributed runtime"
# kubectl create with stdin + generateName returns the materialised name.
TJ_YAML=$(cat <<YAML
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
metadata:
  generateName: c2-mnist-
  namespace: ${NS}
spec:
  runtimeRef:
    apiGroup: trainer.kubeflow.org
    kind: ClusterTrainingRuntime
    name: torch-distributed
  suspend: false
  trainer:
    numNodes: 1
    command:
      - python
      - -c
      - |
$(printf '%s\n' "${TRAIN_PY}" | sed 's/^/        /')
    resourcesPerNode:
      requests:
        cpu: "1"
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi
YAML
)
TJ_NAME=$(printf '%s' "${TJ_YAML}" | retry_create gpu_kc -o jsonpath='{.metadata.name}')
log "C2: trainjob=${TJ_NAME}"

cleanup() {
  gpu_kc -n "${NS}" delete trainjob "${TJ_NAME}" --ignore-not-found --wait=false || true
}
trap cleanup EXIT

log "C2: waiting for jobset pod..."
deadline=$((SECONDS + 600))
pod=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  pod="$(trainjob_pod gpu_kc "${NS}" "${TJ_NAME}")"
  [ -n "${pod}" ] && break
  sleep 5
done
[ -z "${pod}" ] && { log "C2: no pod appeared"; exit 1; }
log "C2: pod=${pod}"

log "C2: waiting for pod terminal state..."
deadline=$((SECONDS + 1200))
phase=""
while [ "${SECONDS}" -lt "${deadline}" ]; do
  phase="$(gpu_kc -n "${NS}" get pod "${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "${phase}" in Succeeded|Failed) break ;; esac
  sleep 10
done
log "C2: pod phase=${phase}"
log "C2: ===== container logs ====="
gpu_kc -n "${NS}" logs "${pod}" --tail=200 || true
log "C2: ===== end logs ====="
[ "${phase}" = "Succeeded" ]
