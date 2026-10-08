import torch
import torch.distributed as dist
from torch import nn
from torch.nn.parallel import DistributedDataParallel
from torch.utils.data import DataLoader, DistributedSampler, TensorDataset


def main():
    dist.init_process_group(backend="gloo")
    rank = dist.get_rank()
    world_size = dist.get_world_size()

    features = torch.linspace(-1, 1, 128).reshape(-1, 1)
    targets = 3 * features + 2
    dataset = TensorDataset(features, targets)
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
    loader = DataLoader(dataset, batch_size=16, sampler=sampler)

    model = DistributedDataParallel(nn.Linear(1, 1))
    optimizer = torch.optim.SGD(model.parameters(), lr=0.1)
    loss_fn = nn.MSELoss()

    for epoch in range(10):
        sampler.set_epoch(epoch)
        for batch_features, batch_targets in loader:
            optimizer.zero_grad()
            loss = loss_fn(model(batch_features), batch_targets)
            loss.backward()
            optimizer.step()

    weight = model.module.weight.item()
    bias = model.module.bias.item()
    print(f"rank={rank}/{world_size} weight={weight:.3f} bias={bias:.3f}", flush=True)
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
