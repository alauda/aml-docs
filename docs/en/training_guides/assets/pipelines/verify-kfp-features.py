"""Verify KFP caching, ParallelFor, and persisted artifact passing."""

import os
import time

from kfp import Client, compiler, dsl


@dsl.component(base_image="docker-mirrors.alauda.cn/library/python:3.12-slim")
def produce_dataset(seed: str, dataset: dsl.Output[dsl.Dataset]) -> None:
    """Write a small dataset to the KFP artifact path."""
    from pathlib import Path

    output = Path(dataset.path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(f"seed={seed}\n", encoding="utf-8")
    dataset.metadata["seed"] = seed


@dsl.component(base_image="docker-mirrors.alauda.cn/library/python:3.12-slim")
def verify_dataset(dataset: dsl.Input[dsl.Dataset], item: int, seed: str) -> str:
    """Read the persisted artifact in one ParallelFor iteration."""
    from pathlib import Path

    content = Path(dataset.path).read_text(encoding="utf-8")
    expected = f"seed={seed}\n"
    if content != expected:
        raise RuntimeError(f"artifact content {content!r} != {expected!r}")
    return f"item={item}:{content.strip()}"


@dsl.pipeline(name="kfp-mechanisms-verification")
def mechanisms_pipeline(seed: str = "alauda-kfp-features") -> None:
    """Produce one artifact and consume it in three parallel tasks."""
    producer = produce_dataset(seed=seed)
    with dsl.ParallelFor(items=[1, 2, 3], parallelism=3) as item:
        verify_dataset(dataset=producer.outputs["dataset"], item=item, seed=seed)


def task_state(task: object) -> str:
    """Return a task state as a stable uppercase string."""
    value = getattr(task, "state", "")
    return str(value).rsplit(".", 1)[-1].upper()


def run_once(
    client: Client, package_path: str, experiment: str, suffix: str, seed: str
) -> object:
    """Submit a cached run and wait for its terminal state."""
    result = client.create_run_from_pipeline_package(
        pipeline_file=package_path,
        arguments={"seed": seed},
        run_name=f"kfp-mechanisms-{suffix}-{int(time.time())}",
        experiment_name=experiment,
        namespace=os.environ["KFP_NAMESPACE"],
        enable_caching=True,
    )
    run = client.wait_for_run_completion(result.run_id, timeout=900, sleep_duration=5)
    if str(run.state).upper() != "SUCCEEDED":
        raise RuntimeError(f"run {result.run_id} ended in {run.state}")
    print(f"run {suffix}: {result.run_id} state={run.state}", flush=True)
    return client.get_run(result.run_id)


def main() -> None:
    """Compile the pipeline, run it twice, and verify the three mechanisms."""
    package_path = "/tmp/kfp-mechanisms-verification.yaml"
    compiler.Compiler().compile(mechanisms_pipeline, package_path=package_path)
    client = Client(host=os.environ["KFP_ENDPOINT"], namespace=os.environ["KFP_NAMESPACE"])
    experiment = f"kfp-mechanisms-{int(time.time())}"
    seed = f"alauda-kfp-features-{time.time_ns()}"

    first = run_once(client, package_path, experiment, "first", seed)
    first_tasks = first.run_details.task_details or []
    for task in first_tasks:
        print(
            f"first task: name={task.display_name} state={task_state(task)} "
            f"outputs={task.outputs or {}}",
            flush=True,
        )

    parallel_tasks = [task for task in first_tasks if task.display_name == "verify-dataset"]
    if len(parallel_tasks) != 3 or any(task_state(task) != "SUCCEEDED" for task in parallel_tasks):
        raise RuntimeError(
            f"ParallelFor expected 3 successful verify-dataset tasks, got {len(parallel_tasks)}"
        )

    producers = [task for task in first_tasks if task.display_name == "produce-dataset"]
    if len(producers) != 1 or task_state(producers[0]) != "SUCCEEDED":
        raise RuntimeError(f"expected one produce-dataset task, got {len(producers)}")
    print(
        "artifact persistence: producer uploaded the Dataset and all 3 consumers read it",
        flush=True,
    )

    second = run_once(client, package_path, experiment, "cached", seed)
    second_tasks = second.run_details.task_details or []
    for task in second_tasks:
        print(f"cached task: name={task.display_name} state={task_state(task)}", flush=True)
    skipped = [task for task in second_tasks if task_state(task) == "SKIPPED"]
    if not skipped:
        raise RuntimeError("second identical run did not report any cached (SKIPPED) task")

    print("PASS: ParallelFor created 3 tasks", flush=True)
    print("PASS: Dataset artifact was persisted and consumed", flush=True)
    print(f"PASS: cache reused {len(skipped)} task execution(s)", flush=True)


if __name__ == "__main__":
    main()
