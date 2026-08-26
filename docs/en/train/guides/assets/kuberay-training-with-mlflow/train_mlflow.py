"""Distributed PyTorch example for a KubeRay RayJob with MLflow tracking."""

import os

import mlflow
import ray
from ray import train
from ray.train import RunConfig, ScalingConfig
from ray.train.torch import TorchTrainer


def train_loop_per_worker(config: dict) -> None:
    import torch
    from torch import nn
    from torch.utils.data import DataLoader, TensorDataset

    torch.manual_seed(int(config["seed"]) + train.get_context().get_world_rank())
    x = torch.linspace(-2, 2, 1024).reshape(-1, 1)
    y = 3 * x + 0.5
    loader = DataLoader(TensorDataset(x, y), batch_size=config["batch_size"], shuffle=True)

    model = train.torch.prepare_model(nn.Linear(1, 1))
    optimizer = torch.optim.SGD(model.parameters(), lr=config["learning_rate"])
    loss_fn = nn.MSELoss()

    for epoch in range(config["epochs"]):
        total_loss = 0.0
        batches = 0
        for features, labels in train.torch.prepare_data_loader(loader):
            optimizer.zero_grad()
            loss = loss_fn(model(features), labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
            batches += 1
        train.report({"loss": total_loss / max(batches, 1), "epoch": epoch + 1})


def main() -> None:
    tracking_uri = os.environ["MLFLOW_TRACKING_URI"]
    workspace = os.environ["MLFLOW_WORKSPACE"]
    experiment = os.environ.get("MLFLOW_EXPERIMENT_NAME", "ray-pytorch")
    run_name = os.environ.get("MLFLOW_RUN_NAME", os.environ.get("RAY_JOB_NAME", "ray-training"))
    workers = int(os.environ.get("RAY_TRAIN_WORKERS", "2"))
    epochs = int(os.environ.get("TRAIN_EPOCHS", "5"))
    learning_rate = float(os.environ.get("TRAIN_LEARNING_RATE", "0.05"))
    batch_size = int(os.environ.get("TRAIN_BATCH_SIZE", "64"))

    ray.init(address="auto")
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_workspace(workspace)
    mlflow.set_experiment(experiment)

    config = {
        "epochs": epochs,
        "learning_rate": learning_rate,
        "batch_size": batch_size,
        "seed": 42,
    }
    trainer = TorchTrainer(
        train_loop_per_worker,
        train_loop_config=config,
        scaling_config=ScalingConfig(num_workers=workers, use_gpu=False),
        run_config=RunConfig(name=run_name),
    )

    with mlflow.start_run(run_name=run_name) as run:
        mlflow.set_tags(
            {
                "ray_job_name": run_name,
                "ray_version": ray.__version__,
                "ray_train_workers": str(workers),
            }
        )
        mlflow.log_params(config)
        result = trainer.fit()
        metrics = result.metrics
        if "loss" in metrics:
            mlflow.log_metric("final_loss", float(metrics["loss"]), step=int(metrics.get("epoch", epochs)))
        mlflow.log_metric("epochs_completed", float(metrics.get("epoch", epochs)))
        print({"mlflow_run_id": run.info.run_id, "metrics": metrics})

    ray.shutdown()


if __name__ == "__main__":
    main()

