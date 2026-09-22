"""Distributed PyTorch example for a KubeRay RayJob that stores and resumes checkpoints."""

from __future__ import annotations

import os

import ray
from ray.train import Checkpoint, CheckpointConfig, FailureConfig, RunConfig, ScalingConfig
from ray.train.torch import TorchTrainer


def train_loop_per_worker(config: dict) -> None:
    import tempfile

    import torch
    from torch import nn
    from torch.utils.data import DataLoader, TensorDataset

    from ray import train

    start_epoch = 0
    model = nn.Linear(1, 1)
    optimizer = torch.optim.SGD(model.parameters(), lr=config["learning_rate"])

    checkpoint = train.get_checkpoint()
    if checkpoint:
        with checkpoint.as_directory() as checkpoint_dir:
            state = torch.load(os.path.join(checkpoint_dir, "state.pt"), map_location="cpu")
            model.load_state_dict(state["model"])
            optimizer.load_state_dict(state["optimizer"])
            start_epoch = int(state["epoch"])
        print(f"[checkpoint] resuming from epoch {start_epoch}", flush=True)
    else:
        print("[checkpoint] no prior checkpoint, starting fresh", flush=True)

    model = train.torch.prepare_model(model)

    torch.manual_seed(int(config["seed"]) + train.get_context().get_world_rank())
    x = torch.linspace(-2, 2, 1024).reshape(-1, 1)
    y = 3 * x + 0.5
    loader = DataLoader(TensorDataset(x, y), batch_size=config["batch_size"], shuffle=True)

    loss_fn = nn.MSELoss()
    crash_at = config.get("crash_at_epoch")

    for epoch in range(start_epoch, config["epochs"]):
        total_loss = 0.0
        batches = 0
        for features, labels in train.torch.prepare_data_loader(loader):
            optimizer.zero_grad()
            loss = loss_fn(model(features), labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
            batches += 1

        metrics = {"loss": total_loss / max(batches, 1), "epoch": epoch + 1}

        with tempfile.TemporaryDirectory() as tmpdir:
            ckpt = None
            # Standard DDP: every rank has the full model, so only rank 0 writes.
            if train.get_context().get_world_rank() == 0:
                to_save = model.module if hasattr(model, "module") else model
                torch.save(
                    {
                        "model": to_save.state_dict(),
                        "optimizer": optimizer.state_dict(),
                        "epoch": epoch + 1,
                    },
                    os.path.join(tmpdir, "state.pt"),
                )
                ckpt = Checkpoint.from_directory(tmpdir)
            train.report(metrics, checkpoint=ckpt)

        # Crash *after* the checkpoint is reported so the retry has something to load.
        # The marker lives on the PVC so a retry of the same experiment does not loop.
        if crash_at is not None and epoch + 1 == crash_at and train.get_context().get_world_rank() == 0:
            marker = os.path.join(
                config["storage_path"], f".injected-crash-{config['run_name']}"
            )
            if not os.path.exists(marker):
                os.makedirs(config["storage_path"], exist_ok=True)
                with open(marker, "w", encoding="utf-8"):
                    pass
                raise RuntimeError(f"injected crash at epoch {crash_at}")


def main() -> None:
    storage_path = os.environ.get("CKPT_DIR", "/mnt/ckpt")
    run_name = os.environ.get("RAY_TRAIN_RUN_NAME", "ray-ckpt-run")
    workers = int(os.environ.get("RAY_TRAIN_WORKERS", "2"))
    epochs = int(os.environ.get("TRAIN_EPOCHS", "8"))
    learning_rate = float(os.environ.get("TRAIN_LEARNING_RATE", "0.05"))
    batch_size = int(os.environ.get("TRAIN_BATCH_SIZE", "64"))
    max_failures = int(os.environ.get("MAX_FAILURES", "3"))
    crash_at = os.environ.get("CRASH_AT_EPOCH")

    experiment_path = os.path.join(storage_path, run_name)
    os.makedirs(storage_path, exist_ok=True)

    ray.init(address="auto")

    train_loop_config = {
        "epochs": epochs,
        "learning_rate": learning_rate,
        "batch_size": batch_size,
        "seed": 42,
        "storage_path": storage_path,
        "run_name": run_name,
        "crash_at_epoch": int(crash_at) if crash_at else None,
    }
    scaling_config = ScalingConfig(num_workers=workers, use_gpu=False)
    run_config = RunConfig(
        name=run_name,
        storage_path=storage_path,
        failure_config=FailureConfig(max_failures=max_failures),
        checkpoint_config=CheckpointConfig(num_to_keep=2),
    )

    # Same script, two behaviours: first submission starts clean; every
    # later submission with the same storage_path + name continues the run.
    if TorchTrainer.can_restore(experiment_path):
        print(f"[checkpoint] restoring experiment from {experiment_path}", flush=True)
        trainer = TorchTrainer.restore(
            experiment_path,
            train_loop_per_worker=train_loop_per_worker,
            train_loop_config=train_loop_config,
            scaling_config=scaling_config,
        )
    else:
        print(f"[checkpoint] starting new experiment at {experiment_path}", flush=True)
        trainer = TorchTrainer(
            train_loop_per_worker,
            train_loop_config=train_loop_config,
            scaling_config=scaling_config,
            run_config=run_config,
        )

    result = trainer.fit()
    print({"metrics": result.metrics, "checkpoint": str(result.checkpoint)}, flush=True)
    ray.shutdown()


if __name__ == "__main__":
    main()
