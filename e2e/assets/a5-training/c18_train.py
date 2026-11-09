import os
import torch
import torch.distributed as dist
import torch.nn as nn
import torch_npu

local_rank = int(os.environ["LOCAL_RANK"])
assert torch.npu.device_count() == int(os.environ["C18_NPU_COUNT"]), (
    f"expected {os.environ['C18_NPU_COUNT']} visible NPUs, got {torch.npu.device_count()}"
)
torch.npu.set_device(local_rank)
device = torch.device("npu", local_rank)
dist.init_process_group(backend="hccl")
print(f"rank={dist.get_rank()} local_rank={local_rank} device={device} world_size={dist.get_world_size()}", flush=True)
assert dist.get_world_size() == int(os.environ["C18_NPU_COUNT"])

model = nn.parallel.DistributedDataParallel(
    nn.Linear(16, 4, bias=False).to(device),
    device_ids=[local_rank],
    output_device=local_rank,
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
    print(f"PASS: {dist.get_world_size()} NPU ranks completed DDP optimizer step and HCCL all_reduce={result.item()}", flush=True)
dist.destroy_process_group()
