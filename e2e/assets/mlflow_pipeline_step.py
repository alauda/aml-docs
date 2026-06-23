#!/usr/bin/env python3
"""Kubeflow Pipeline step: open an MLflow run from the pipeline-run context and
log params + a metric + an artifact, tagged with the KFP pipeline run id.

Auth: the in-cluster MLflow tracking Service in `user_identity_token` mode.
The step authenticates with a workspace ServiceAccount token (MLFLOW_TRACKING_TOKEN,
sent as Authorization: Bearer) against the proxy-bypass Service, and selects the
workspace with MLFLOW_WORKSPACE (X-MLFLOW-WORKSPACE). No oauth2-proxy / Dex / ROPC.

Env:
  MLFLOW_TRACKING_URI    in-cluster Service URL (proxy-bypass), e.g.
                         http://mlflow-e2e-direct.kubeflow:5000
  MLFLOW_TRACKING_TOKEN  workspace ServiceAccount token (Bearer)
  MLFLOW_WORKSPACE       workspace namespace (mlflow-enabled=true)
  KFP_RUN_ID             the pipeline run id. Injected by the IR's kubernetes
                         platform spec via the Downward API from the workflow pod
                         label `pipeline/runid`. (The KFP {{$.pipeline_job_uuid}}
                         placeholder is NOT resolved for raw container components,
                         so the label is the reliable source.)
  MLFLOW_EXPERIMENT_NAME experiment name (optional)
"""
import json, os, sys, tempfile

import mlflow

uri = os.environ.get("MLFLOW_TRACKING_URI", "http://mlflow-e2e-direct.kubeflow:5000")
workspace = os.environ.get("MLFLOW_WORKSPACE", "mlflow-e2e")
experiment = os.environ.get("MLFLOW_EXPERIMENT_NAME", "aip-mlflow-pipeline-8.1.2")
kfp_run_id = os.environ.get("KFP_RUN_ID", "unknown")
# allow CLI overrides: --kfp-run-id=... --experiment=... --workspace=... --tracking-uri=...
for a in sys.argv[1:]:
    if a.startswith("--kfp-run-id="):   kfp_run_id = a.split("=", 1)[1]
    elif a.startswith("--experiment="): experiment = a.split("=", 1)[1]
    elif a.startswith("--workspace="):  workspace = a.split("=", 1)[1]
    elif a.startswith("--tracking-uri="): uri = a.split("=", 1)[1]

mlflow.set_tracking_uri(uri)
mlflow.set_workspace(workspace)            # -> X-MLFLOW-WORKSPACE ; needs mlflow>=3.10
try:
    mlflow.set_experiment(experiment)
except mlflow.exceptions.MlflowException:
    # The experiment name may be soft-deleted (a tombstone from a previous run);
    # MLflow refuses to reuse a deleted name, so restore it and retry.
    from mlflow import MlflowClient
    from mlflow.entities import ViewType
    client = MlflowClient()
    found = client.search_experiments(view_type=ViewType.DELETED_ONLY,
                                       filter_string=f"name = '{experiment}'")
    if found:
        client.restore_experiment(found[0].experiment_id)
    mlflow.set_experiment(experiment)

with mlflow.start_run(run_name=f"kfp-{kfp_run_id}") as run:
    # The integration linkage: tag the MLflow run with the KFP pipeline run id.
    mlflow.set_tag("kfp_run_id", kfp_run_id)
    mlflow.set_tag("source", "kubeflow-pipeline")
    mlflow.log_param("model_name", "demo-model")
    mlflow.log_param("learning_rate", 0.001)
    mlflow.log_param("epochs", 3)
    for epoch in range(1, 4):
        mlflow.log_metric("accuracy", 0.80 + 0.05 * epoch, step=epoch)
    mlflow.log_metric("final_accuracy", 0.95)

    # An artifact tied to this run. NOTE: on an install where the workspace
    # tracking server uses a server-local artifact root (no --serve-artifacts
    # proxy), a remote client cannot upload artifacts. We therefore (1) try the
    # normal upload, and (2) ALWAYS record the same payload as the run tag
    # `kfp_run_context` so the artifact content is verifiable over the REST API
    # regardless of the artifact-store configuration.
    run_context = {"kfp_run_id": kfp_run_id, "workspace": workspace,
                   "experiment": experiment}
    mlflow.set_tag("kfp_run_context", json.dumps(run_context))
    d = tempfile.mkdtemp()
    p = os.path.join(d, "run_context.json")
    with open(p, "w") as f:
        json.dump(run_context, f, indent=2)
    artifact_ok = True
    try:
        mlflow.log_artifact(p, artifact_path="context")
    except Exception as e:          # non-fatal: server-local artifact root
        artifact_ok = False
        print(f"ARTIFACT_UPLOAD_SKIPPED: {type(e).__name__}: {e}", file=sys.stderr)

    info = run.info
    print("MLFLOW_RUN_ID="        + info.run_id)
    print("MLFLOW_EXPERIMENT_ID=" + info.experiment_id)
    print("KFP_RUN_ID="           + kfp_run_id)
    print("ARTIFACT_UPLOADED="    + str(artifact_ok))
    print("ARTIFACT_URI="         + mlflow.get_artifact_uri())

print("STEP_OK")
