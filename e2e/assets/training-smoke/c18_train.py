import os
import torch
import torch.distributed as dist
import torch.nn as nn
device_type = {"gpu": "cuda", "npu": "npu", "cpu": "cpu"}[os.environ["TRAINING_DEVICE"]]
if device_type == "npu":
    import torch_npu

local_rank = int(os.environ["LOCAL_RANK"])
count = int(os.environ["TRAINING_PROCESS_COUNT"])
if device_type != "cpu":
    accelerator = getattr(torch, device_type)
    assert accelerator.is_available(), f"{device_type} is unavailable"
    assert accelerator.device_count() == count, f"expected {count} visible {device_type} devices"
    accelerator.set_device(local_rank)
device = torch.device(device_type, local_rank) if device_type != "cpu" else torch.device("cpu")
backend = {"cuda": "nccl", "npu": "hccl", "cpu": "gloo"}[device_type]
dist.init_process_group(backend=backend)
print(f"rank={dist.get_rank()} local_rank={local_rank} device={device} world_size={dist.get_world_size()}", flush=True)
assert dist.get_world_size() == int(os.environ["TRAINING_PROCESS_COUNT"])

model = nn.parallel.DistributedDataParallel(
    nn.Linear(16, 4, bias=False).to(device),
    device_ids=[local_rank] if device_type != "cpu" else None,
    output_device=local_rank if device_type != "cpu" else None,
)
before = [param.detach().clone() for param in model.parameters()]
optimizer = torch.optim.SGD(model.parameters(), lr=0.01)
x = torch.full((8, 16), float(dist.get_rank() + 1), device=device)
loss = model(x).square().mean()
optimizer.zero_grad()
loss.backward()
optimizer.step()
assert any(not torch.equal(old, param) for old, param in zip(before, model.parameters())), "weights did not update"
assert torch.isfinite(loss).item(), loss
for param in model.parameters():
    assert param.grad is not None and torch.isfinite(param.grad).all().item()
    peers = [torch.empty_like(param) for _ in range(dist.get_world_size())]
    dist.all_gather(peers, param.detach())
    assert all(torch.allclose(param, peer) for peer in peers), 'DDP parameters diverged'

result = torch.tensor([float(dist.get_rank() + 1)], device=device)
dist.all_reduce(result, op=dist.ReduceOp.SUM)
assert result.item() == dist.get_world_size() * (dist.get_world_size() + 1) / 2
dist.barrier()
if dist.get_rank() == 0:
    print(f"PASS: C18 completed {dist.get_world_size()} ranks, DDP optimizer step and all_reduce={result.item()}", flush=True)
dist.destroy_process_group()
