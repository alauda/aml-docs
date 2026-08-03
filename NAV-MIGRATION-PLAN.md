# Alauda AI 文档导航重构方案（场景化 / RHOAI 风格）

> 状态：**待评审**。本文档不参与站点构建（位于仓库根目录，`doom` 只读 `docs/`）。

## 1. 设计原则

参照 Red Hat OpenShift AI 3.x 的组织方式，顶层导航按**用户场景/生命周期阶段**划分，
而非按功能模块或上游组件划分。与 RHOAI 的唯一结构性差异：Alauda AI 的 19 个组件是
独立安装的 operator / cluster plugin，因此每个场景保留一个 `components/` 子目录承载
该场景所依赖组件的介绍与安装文档；RHOAI 因组件由 `DataScienceCluster` 统一开关，无此需要。

组件归属规则：**按任务文档的主场景归位，只存放一份**。次要场景通过任务页的 Prerequisites 
内联链接与章节导语指向，不设置仅含跳转的占位页。

## 2. 顶层结构

| # | 章节 | 目录 | 页数 | 含组件 |
|---|---|---|---|---|
| 1 | Overview 概述 | `overview/` | 5 | — |
| 2 | Plan 规划与选型 | `plan/` | 12 | — |
| 3 | Install 安装 | `installation/` | 6 | — |
| 4 | Upgrade 升级与卸载 | `upgrade/` | 5 | — |
| 5 | Administer 平台管理 | `administer/` | 13 | — |
| 6 | Develop 开发 | `develop/` | 56 | data_science_pipelines, feast, kubeflow, kuberay, label_studio, mlflow, spark_operator |
| 7 | Train 训练与调优 | `train/` | 30 | jobset, kueue, volcano |
| 8 | Deploy 部署与推理 | `deploy/` | 48 | envoy_ai_gateway, infernex_bridge, kserve, lws |
| 9 | Build AI Applications 构建 AI 应用 | `ai_applications/` | 23 | dify, kagenti, llama_stack, mcp_lifecycle_operator |
| 10 | Evaluate & Safety 评测与安全 | `evaluate_safety/` | 9 | trustyai |
| 11 | Monitor 监控与运维 | `monitor/` | 11 | — |
| 12 | API Reference | `apis/` | 13 | — |

合计 232 页（含 2 篇 `.md`：`plan/supported_configurations.md`、`train/guides/kubeflow-trainer-quick-start.md`，doom 的路由 `**/*.md{,x}` 一并收录）。

## 3. 逐文件迁移表

> 注：本表为第一版（PR #299 首次提交）的映射；其中 `how_to/` / `functions/` 相关条目已被 §8 的二次调整取代。


### Overview 概述 — `overview/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `overview/architecture.mdx` | `overview/architecture.mdx` |  | 1 |
| `overview/index.mdx` | `overview/index.mdx` |  |  |
| `overview/intro.mdx` | `overview/intro.mdx` |  |  |
| `overview/quick_start.mdx` | `overview/quick_start.mdx` |  | 1 |
| `overview/release_notes.mdx` | `overview/release_notes.mdx` |  |  |

### Plan 规划与选型 — `plan/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `infrastructure_management/device_management/hami.mdx` | `plan/device_options/hami.mdx` |  |  |
| `infrastructure_management/device_management/index.mdx` | `plan/device_options/index.mdx` |  |  |
| `infrastructure_management/device_management/pgpu.mdx` | `plan/device_options/pgpu.mdx` |  |  |
| `learn/glossary.mdx` | `plan/glossary.mdx` |  |  |
| `learn/supported-configurations-for-2.x.md` | `plan/supported_configurations.md` | 重命名 |  |
| `model_inference/inference_guide/deepseek-v4-flash-w4a8.mdx` | `plan/validated_models/deepseek-v4-flash-w4a8.mdx` |  |  |
| `model_inference/inference_guide/deepseek-v4-flash-w8a8.mdx` | `plan/validated_models/deepseek-v4-flash-w8a8.mdx` |  |  |
| `model_inference/inference_guide/index.mdx` | `plan/validated_models/index.mdx` |  | 8 |
| `model_inference/inference_guide/minimax-m2.5-w8a8.mdx` | `plan/validated_models/minimax-m2.5-w8a8.mdx` |  |  |
| `model_inference/inference_guide/qwen3-32b.mdx` | `plan/validated_models/qwen3-32b.mdx` |  |  |
| `model_inference/inference_guide/qwen3-6-27b-w8a8.mdx` | `plan/validated_models/qwen3-6-27b-w8a8.mdx` |  |  |

### Install 安装 — `installation/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `installation/ai-cluster.mdx` | `installation/ai-cluster.mdx` |  | 3 |
| `installation/ai-essentials.mdx` | `installation/ai-essentials.mdx` |  |  |
| `installation/index.mdx` | `installation/index.mdx` |  | 5 |
| `installation/pre-configuration.mdx` | `installation/pre-configuration.mdx` |  |  |
| `installation/tools.mdx` | `installation/tools.mdx` |  |  |
| `installation/workbench.mdx` | `installation/workbench.mdx` |  |  |

### Upgrade 升级与卸载 — `upgrade/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `upgrade/index.mdx` | `upgrade/index.mdx` |  |  |
| `upgrade/migrating-to-knative-operator.mdx` | `upgrade/migrating-to-knative-operator.mdx` |  | 1 |
| `upgrade/uninstall.mdx` | `upgrade/uninstall.mdx` |  |  |
| `upgrade/upgrade-from-previous-version.mdx` | `upgrade/upgrade-from-previous-version.mdx` |  | 6 |
| `workbench/upgrade.mdx` | `upgrade/workbench.mdx` | 移入 Upgrade 章 | 1 |

### Administer 平台管理 — `administer/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `infrastructure_management/hardware_profile/functions/hardware_profile.mdx` | `administer/hardware_profile/functions/hardware_profile.mdx` |  |  |
| `infrastructure_management/hardware_profile/functions/index.mdx` | `administer/hardware_profile/functions/index.mdx` |  |  |
| `infrastructure_management/hardware_profile/how_to/cpu_and_gpu_profiles.mdx` | `administer/hardware_profile/how_to/cpu_and_gpu_profiles.mdx` |  |  |
| `infrastructure_management/hardware_profile/how_to/create_hardware_profile_cli.mdx` | `administer/hardware_profile/how_to/create_hardware_profile_cli.mdx` |  |  |
| `infrastructure_management/hardware_profile/how_to/index.mdx` | `administer/hardware_profile/how_to/index.mdx` |  |  |
| `infrastructure_management/hardware_profile/how_to/schedule_to_specific_gpu_nodes.mdx` | `administer/hardware_profile/how_to/schedule_to_specific_gpu_nodes.mdx` |  |  |
| `infrastructure_management/hardware_profile/index.mdx` | `administer/hardware_profile/index.mdx` |  |  |
| `infrastructure_management/hardware_profile/intro.mdx` | `administer/hardware_profile/intro.mdx` |  |  |
| `ai_applications/kagenti/how_to/enable_secure_profile.mdx` | `administer/how_to/enable_secure_profile.mdx` |  | 5 |
| `ai_applications/kagenti/how_to/install_secure_dependencies.mdx` | `administer/how_to/install_secure_dependencies.mdx` |  | 2 |
| `data_experiments/mlflow/how_to/workspaces.mdx` | `administer/how_to/mlflow_workspaces.mdx` |  | 3 |
| `infrastructure_management/multi_tenant/functions/index.mdx` | `administer/multi_tenant/functions/index.mdx` |  |  |
| `infrastructure_management/multi_tenant/functions/namespace-manage.mdx` | `administer/multi_tenant/functions/namespace-manage.mdx` |  |  |
| `infrastructure_management/multi_tenant/index.mdx` | `administer/multi_tenant/index.mdx` |  |  |

### Develop 开发 — `develop/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `training_pipelines/agentic_mlops/coding-agents-with-inference-service.mdx` | `develop/agentic_mlops/coding-agents-with-inference-service.mdx` |  | 30 |
| `training_pipelines/agentic_mlops/index.mdx` | `develop/agentic_mlops/index.mdx` |  |  |
| `training_pipelines/agentic_mlops/mlops-with-coding-agents.mdx` | `develop/agentic_mlops/mlops-with-coding-agents.mdx` |  | 33 |
| `training_pipelines/data_science_pipelines/index.mdx` | `develop/components/data_science_pipelines/index.mdx` |  |  |
| `training_pipelines/data_science_pipelines/install.mdx` | `develop/components/data_science_pipelines/install.mdx` |  | 2 |
| `training_pipelines/data_science_pipelines/intro.mdx` | `develop/components/data_science_pipelines/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `data_experiments/feast/index.mdx` | `develop/components/feast/index.mdx` |  |  |
| `data_experiments/feast/install.mdx` | `develop/components/feast/install.mdx` |  | 1 |
| `data_experiments/feast/intro.mdx` | `develop/components/feast/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 2 |
| `data_experiments/feast/quickstart.mdx` | `develop/components/feast/quickstart.mdx` |  | 1 |
| `training_pipelines/kubeflow/faq.mdx` | `develop/components/kubeflow/faq.mdx` |  |  |
| `training_pipelines/kubeflow/index.mdx` | `develop/components/kubeflow/index.mdx` |  |  |
| `training_pipelines/kubeflow/install.mdx` | `develop/components/kubeflow/install.mdx` |  | 1 |
| `training_pipelines/kubeflow/intro.mdx` | `develop/components/kubeflow/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `training_pipelines/kubeflow/upgrade.mdx` | `develop/components/kubeflow/upgrade.mdx` |  | 1 |
| `training_pipelines/kuberay/index.mdx` | `develop/components/kuberay/index.mdx` |  |  |
| `training_pipelines/kuberay/install.mdx` | `develop/components/kuberay/install.mdx` |  |  |
| `training_pipelines/kuberay/intro.mdx` | `develop/components/kuberay/intro.mdx` | ★标题 "Introduction" 需改为组件名 |  |
| `data_experiments/label_studio/overview/features.mdx` | `develop/components/label_studio/features.mdx` | 打平 overview/ 子目录 |  |
| `data_experiments/label_studio/index.mdx` | `develop/components/label_studio/index.mdx` |  |  |
| `data_experiments/label_studio/install.mdx` | `develop/components/label_studio/install.mdx` |  |  |
| `data_experiments/label_studio/overview/intro.mdx` | `develop/components/label_studio/intro.mdx` | 打平 overview/ 子目录 ; ★标题 "Introduction" 需改为组件名 |  |
| `data_experiments/label_studio/quickstart.mdx` | `develop/components/label_studio/quickstart.mdx` |  |  |
| `data_experiments/mlflow/index.mdx` | `develop/components/mlflow/index.mdx` |  |  |
| `data_experiments/mlflow/install.mdx` | `develop/components/mlflow/install.mdx` |  | 2 |
| `data_experiments/mlflow/intro.mdx` | `develop/components/mlflow/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 3 |
| `training_pipelines/spark_operator/index.mdx` | `develop/components/spark_operator/index.mdx` |  |  |
| `training_pipelines/spark_operator/install.mdx` | `develop/components/spark_operator/install.mdx` |  | 1 |
| `training_pipelines/spark_operator/intro.mdx` | `develop/components/spark_operator/intro.mdx` | ★标题 "Introduction" 需改为组件名 |  |
| `workbench/connections/how_to/index.mdx` | `develop/connections/how_to/index.mdx` |  |  |
| `workbench/connections/how_to/using_connections.mdx` | `develop/connections/how_to/using_connections.mdx` |  | 1 |
| `workbench/connections/index.mdx` | `develop/connections/index.mdx` |  |  |
| `workbench/connections/overview/index.mdx` | `develop/connections/overview/index.mdx` |  |  |
| `workbench/connections/overview/intro.mdx` | `develop/connections/overview/intro.mdx` |  | 1 |
| `data_experiments/mlflow/how_to/agent-tracing.mdx` | `develop/experiment_tracking/agent-tracing.mdx` |  | 3 |
| `data_experiments/mlflow/how_to/mlflow-python-sdk.mdx` | `develop/experiment_tracking/mlflow-python-sdk.mdx` |  | 4 |
| `data_experiments/mlflow/how_to/pipelines-mlflow-integration.mdx` | `develop/experiment_tracking/pipelines-mlflow-integration.mdx` |  | 14 |
| `training_pipelines/kuberay/how_to/codeflare-sdk-tutorial.mdx` | `develop/how_to/codeflare-sdk-tutorial.mdx` |  | 2 |
| `training_pipelines/data_science_pipelines/how_to/create_dspa.mdx` | `develop/how_to/create_dspa.mdx` |  | 1 |
| `training_pipelines/kubeflow/how_to/model-registry.mdx` | `develop/how_to/model-registry.mdx` |  |  |
| `training_pipelines/kubeflow/how_to/notebooks.mdx` | `develop/how_to/notebooks.mdx` |  |  |
| `training_pipelines/kubeflow/how_to/pipelines.mdx` | `develop/how_to/pipelines.mdx` |  |  |
| `training_pipelines/spark_operator/how_to/run_spark_application.mdx` | `develop/how_to/run_spark_application.mdx` |  | 1 |
| `training_pipelines/kueue/how_to/tekton.mdx` | `develop/how_to/tekton.mdx` |  |  |
| `training_pipelines/kubeflow/how_to/tensorboards.mdx` | `develop/how_to/tensorboards.mdx` |  |  |
| `model_inference/model_management/how_to/upload_models_using_notebook.mdx` | `develop/how_to/upload_models_using_notebook.mdx` |  |  |
| `training_pipelines/kubeflow/how_to/volumes-kserve.mdx` | `develop/how_to/volumes-kserve.mdx` |  |  |
| `workbench/how_to/create_workbench.mdx` | `develop/workbench/how_to/create_workbench.mdx` |  |  |
| `workbench/how_to/index.mdx` | `develop/workbench/how_to/index.mdx` |  |  |
| `workbench/how_to/run-kubeflow-pipelines-with-elyra.mdx` | `develop/workbench/how_to/run-kubeflow-pipelines-with-elyra.mdx` |  | 9 |
| `workbench/index.mdx` | `develop/workbench/index.mdx` |  |  |
| `workbench/overview/index.mdx` | `develop/workbench/overview/index.mdx` |  |  |
| `workbench/overview/intro.mdx` | `develop/workbench/overview/intro.mdx` |  |  |

### Train 训练与调优 — `train/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `training_pipelines/jobset/index.mdx` | `train/components/jobset/index.mdx` |  |  |
| `training_pipelines/jobset/install.mdx` | `train/components/jobset/install.mdx` |  | 1 |
| `training_pipelines/jobset/intro.mdx` | `train/components/jobset/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 3 |
| `training_pipelines/jobset/quickstart.mdx` | `train/components/jobset/quickstart.mdx` |  | 2 |
| `training_pipelines/kueue/index.mdx` | `train/components/kueue/index.mdx` |  |  |
| `training_pipelines/kueue/install.mdx` | `train/components/kueue/install.mdx` |  |  |
| `training_pipelines/kueue/intro.mdx` | `train/components/kueue/intro.mdx` | ★标题 "Introduction" 需改为组件名 |  |
| `training_pipelines/volcano/index.mdx` | `train/components/volcano/index.mdx` |  |  |
| `training_pipelines/volcano/install.mdx` | `train/components/volcano/install.mdx` |  |  |
| `training_pipelines/volcano/intro.mdx` | `train/components/volcano/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `training_pipelines/training_guides/checkpointing-and-resuming.mdx` | `train/how_to/checkpointing-and-resuming.mdx` |  | 6 |
| `training_pipelines/training_guides/fine-tune-and-pretrain-llms-on-ascend-npu.mdx` | `train/how_to/fine-tune-and-pretrain-llms-on-ascend-npu.mdx` |  | 4 |
| `training_pipelines/training_guides/fine-tune-with-trainer-v2.mdx` | `train/how_to/fine-tune-with-trainer-v2.mdx` |  | 1 |
| `training_pipelines/training_guides/fine-tuning-pipeline-with-mlflow-trustyai.mdx` | `train/how_to/fine-tuning-pipeline-with-mlflow-trustyai.mdx` |  | 22 |
| `training_pipelines/training_guides/fine-tuning-using-notebooks.mdx` | `train/how_to/fine-tuning-using-notebooks.mdx` |  | 7 |
| `training_pipelines/training_guides/gpu-slicing-with-dra.mdx` | `train/how_to/gpu-slicing-with-dra.mdx` |  | 4 |
| `training_pipelines/training_guides/index.mdx` | `train/how_to/index.mdx` |  | 13 |
| `training_pipelines/training_guides/kfp-execution-and-storage.mdx` | `train/how_to/kfp-execution-and-storage.mdx` |  |  |
| `training_pipelines/training_guides/kubeflow-trainer-quick-start.md` | `train/how_to/kubeflow-trainer-quick-start.md` |  |  |
| `training_pipelines/training_guides/preemptible-trainjobs-with-kueue.mdx` | `train/how_to/preemptible-trainjobs-with-kueue.mdx` |  | 4 |
| `training_pipelines/training_guides/reusable-pipeline-components.mdx` | `train/how_to/reusable-pipeline-components.mdx` |  | 1 |
| `training_pipelines/training_guides/training-hub-fine-tuning.mdx` | `train/how_to/training-hub-fine-tuning.mdx` |  | 2 |
| `training_pipelines/training_guides/training-runtimes.mdx` | `train/how_to/training-runtimes.mdx` |  | 3 |
| `training_pipelines/kueue/how_to/config_quotas.mdx` | `train/quota_scheduling/config_quotas.mdx` |  |  |
| `training_pipelines/kueue/how_to/fair_sharing.mdx` | `train/quota_scheduling/fair_sharing.mdx` |  |  |
| `training_pipelines/kueue/how_to/gang_scheduling.mdx` | `train/quota_scheduling/gang_scheduling.mdx` |  |  |
| `training_pipelines/kueue/how_to/npu_quota.mdx` | `train/quota_scheduling/npu_quota.mdx` |  |  |
| `training_pipelines/kueue/how_to/setup_rbac.mdx` | `train/quota_scheduling/setup_rbac.mdx` |  |  |
| `training_pipelines/kueue/how_to/using_cohorts.mdx` | `train/quota_scheduling/using_cohorts.mdx` |  |  |

### Deploy 部署与推理 — `deploy/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `model_inference/envoy_ai_gateway/index.mdx` | `deploy/components/envoy_ai_gateway/index.mdx` |  |  |
| `model_inference/envoy_ai_gateway/install.mdx` | `deploy/components/envoy_ai_gateway/install.mdx` |  |  |
| `model_inference/envoy_ai_gateway/intro.mdx` | `deploy/components/envoy_ai_gateway/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 7 |
| `model_inference/infernex_bridge/index.mdx` | `deploy/components/infernex_bridge/index.mdx` |  |  |
| `model_inference/infernex_bridge/install.mdx` | `deploy/components/infernex_bridge/install.mdx` |  | 3 |
| `model_inference/infernex_bridge/intro.mdx` | `deploy/components/infernex_bridge/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `model_inference/kserve/index.mdx` | `deploy/components/kserve/index.mdx` |  |  |
| `model_inference/kserve/install.mdx` | `deploy/components/kserve/install.mdx` |  | 2 |
| `model_inference/kserve/intro.mdx` | `deploy/components/kserve/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `model_inference/lws/index.mdx` | `deploy/components/lws/index.mdx` |  |  |
| `model_inference/lws/install.mdx` | `deploy/components/lws/install.mdx` |  |  |
| `model_inference/lws/intro.mdx` | `deploy/components/lws/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 2 |
| `model_inference/envoy_ai_gateway/how_to/cost_management_chargeback.mdx` | `deploy/gateway/cost_management_chargeback.mdx` |  | 4 |
| `model_inference/envoy_ai_gateway/how_to/external_provider_routing.mdx` | `deploy/gateway/external_provider_routing.mdx` |  | 3 |
| `model_inference/envoy_ai_gateway/how_to/identity_authentication.mdx` | `deploy/gateway/identity_authentication.mdx` |  | 6 |
| `model_inference/envoy_ai_gateway/how_to/token_rate_limiting.mdx` | `deploy/gateway/token_rate_limiting.mdx` |  | 6 |
| `model_inference/envoy_ai_gateway/how_to/usage_metering.mdx` | `deploy/gateway/usage_metering.mdx` |  | 8 |
| `training_pipelines/kueue/how_to/isvc.mdx` | `deploy/how_to/isvc.mdx` |  |  |
| `model_inference/inference_service/functions/index.mdx` | `deploy/inference_service/functions/index.mdx` |  |  |
| `model_inference/inference_service/functions/inference_service.mdx` | `deploy/inference_service/functions/inference_service.mdx` |  |  |
| `model_inference/inference_service/how_to/accurately_schedule.mdx` | `deploy/inference_service/how_to/accurately_schedule.mdx` |  |  |
| `model_inference/inference_service/how_to/autoscale_settings.mdx` | `deploy/inference_service/how_to/autoscale_settings.mdx` |  |  |
| `model_inference/inference_service/how_to/create_inference_service_cli.mdx` | `deploy/inference_service/how_to/create_inference_service_cli.mdx` |  |  |
| `model_inference/inference_service/how_to/custom_inference_runtime.mdx` | `deploy/inference_service/how_to/custom_inference_runtime.mdx` |  |  |
| `model_inference/inference_service/how_to/external_access_inference_service.mdx` | `deploy/inference_service/how_to/external_access_inference_service.mdx` |  |  |
| `model_inference/inference_service/how_to/index.mdx` | `deploy/inference_service/how_to/index.mdx` |  |  |
| `model_inference/inference_service/how_to/keda_autoscaling.mdx` | `deploy/inference_service/how_to/keda_autoscaling.mdx` |  |  |
| `model_inference/inference_service/how_to/using_modelcar.mdx` | `deploy/inference_service/how_to/using_modelcar.mdx` |  | 2 |
| `model_inference/inference_service/how_to/vllm_expert_parallel.mdx` | `deploy/inference_service/how_to/vllm_expert_parallel.mdx` |  | 3 |
| `model_inference/inference_service/how_to/vllm_speculative_decoding.mdx` | `deploy/inference_service/how_to/vllm_speculative_decoding.mdx` |  | 6 |
| `model_inference/inference_service/index.mdx` | `deploy/inference_service/index.mdx` |  |  |
| `model_inference/inference_service/intro.mdx` | `deploy/inference_service/intro.mdx` |  |  |
| `model_inference/inference_service/trouble_shooting/index.mdx` | `deploy/inference_service/trouble_shooting/index.mdx` |  |  |
| `model_inference/inference_service/trouble_shooting/infer_timeout.mdx` | `deploy/inference_service/trouble_shooting/infer_timeout.mdx` |  |  |
| `model_inference/inference_service/trouble_shooting/pod_security_admission_violation.mdx` | `deploy/inference_service/trouble_shooting/pod_security_admission_violation.mdx` |  |  |
| `model_inference/maas/index.mdx` | `deploy/maas/index.mdx` |  |  |
| `model_inference/maas/intro.mdx` | `deploy/maas/intro.mdx` |  |  |
| `model_inference/llm_compressor/how_to/compressor_by_workbench.mdx` | `deploy/model_compression/compressor_by_workbench.mdx` |  | 4 |
| `model_inference/llm_compressor/how_to/index.mdx` | `deploy/model_compression/how_to/index.mdx` |  |  |
| `model_inference/llm_compressor/index.mdx` | `deploy/model_compression/index.mdx` |  |  |
| `model_inference/llm_compressor/intro.mdx` | `deploy/model_compression/intro.mdx` |  |  |
| `model_inference/model_management/functions/index.mdx` | `deploy/model_management/functions/index.mdx` |  |  |
| `model_inference/model_management/functions/model_repository.mdx` | `deploy/model_management/functions/model_repository.mdx` |  | 1 |
| `model_inference/model_management/functions/model_storage.mdx` | `deploy/model_management/functions/model_storage.mdx` |  | 5 |
| `model_inference/model_management/how_to/index.mdx` | `deploy/model_management/how_to/index.mdx` |  |  |
| `model_inference/model_management/how_to/share_models.mdx` | `deploy/model_management/how_to/share_models.mdx` |  |  |
| `model_inference/model_management/index.mdx` | `deploy/model_management/index.mdx` |  |  |
| `model_inference/model_management/intro.mdx` | `deploy/model_management/intro.mdx` |  |  |
| `model_inference/overview/features.mdx` | `deploy/overview/features.mdx` |  |  |
| `model_inference/overview/index.mdx` | `deploy/overview/index.mdx` |  |  |
| `model_inference/overview/intro.mdx` | `deploy/overview/intro.mdx` |  |  |

### Build AI Applications 构建 AI 应用 — `ai_applications/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `ai_applications/dify/overview/features.mdx` | `ai_applications/components/dify/features.mdx` | 打平 overview/ 子目录 | 1 |
| `ai_applications/dify/index.mdx` | `ai_applications/components/dify/index.mdx` |  |  |
| `ai_applications/dify/install.mdx` | `ai_applications/components/dify/install.mdx` |  | 1 |
| `ai_applications/dify/overview/intro.mdx` | `ai_applications/components/dify/intro.mdx` | 打平 overview/ 子目录 ; ★标题 "Introduction" 需改为组件名 | 3 |
| `ai_applications/kagenti/index.mdx` | `ai_applications/components/kagenti/index.mdx` |  |  |
| `ai_applications/kagenti/install.mdx` | `ai_applications/components/kagenti/install.mdx` |  | 3 |
| `ai_applications/kagenti/intro.mdx` | `ai_applications/components/kagenti/intro.mdx` | ★标题 "Introduction" 需改为组件名 |  |
| `ai_applications/kagenti/security_architecture.mdx` | `ai_applications/components/kagenti/security_architecture.mdx` |  | 4 |
| `ai_applications/llama_stack/overview/features.mdx` | `ai_applications/components/llama_stack/features.mdx` | 打平 overview/ 子目录 |  |
| `ai_applications/llama_stack/index.mdx` | `ai_applications/components/llama_stack/index.mdx` |  |  |
| `ai_applications/llama_stack/install.mdx` | `ai_applications/components/llama_stack/install.mdx` |  | 2 |
| `ai_applications/llama_stack/overview/intro.mdx` | `ai_applications/components/llama_stack/intro.mdx` | 打平 overview/ 子目录 ; ★标题 "Introduction" 需改为组件名 |  |
| `ai_applications/llama_stack/quickstart.mdx` | `ai_applications/components/llama_stack/quickstart.mdx` |  | 2 |
| `ai_applications/mcp_lifecycle_operator/index.mdx` | `ai_applications/components/mcp_lifecycle_operator/index.mdx` |  |  |
| `ai_applications/mcp_lifecycle_operator/install.mdx` | `ai_applications/components/mcp_lifecycle_operator/install.mdx` |  |  |
| `ai_applications/mcp_lifecycle_operator/intro.mdx` | `ai_applications/components/mcp_lifecycle_operator/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 1 |
| `ai_applications/mcp_lifecycle_operator/quickstart.mdx` | `ai_applications/components/mcp_lifecycle_operator/quickstart.mdx` |  | 1 |
| `ai_applications/kagenti/how_to/demo_advanced_secure_profile.mdx` | `ai_applications/how_to/demo_advanced_secure_profile.mdx` |  | 6 |
| `ai_applications/kagenti/how_to/demo_with_secure_profile.mdx` | `ai_applications/how_to/demo_with_secure_profile.mdx` |  | 10 |
| `ai_applications/kagenti/how_to/deploy_agent_with_agentruntime.mdx` | `ai_applications/how_to/deploy_agent_with_agentruntime.mdx` |  | 8 |
| `ai_applications/kagenti/how_to/envoy_ai_gateway_mcp.mdx` | `ai_applications/how_to/envoy_ai_gateway_mcp.mdx` |  |  |

### Evaluate & Safety 评测与安全 — `evaluate_safety/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `ai_applications/trustyai/ai-guardrails.mdx` | `evaluate_safety/ai_guardrails.mdx` | 重命名（连字符→下划线） | 1 |
| `ai_applications/trustyai/index.mdx` | `evaluate_safety/components/trustyai/index.mdx` |  |  |
| `ai_applications/trustyai/install.mdx` | `evaluate_safety/components/trustyai/install.mdx` |  | 4 |
| `ai_applications/trustyai/intro.mdx` | `evaluate_safety/components/trustyai/intro.mdx` | ★标题 "Introduction" 需改为组件名 | 5 |
| `ai_applications/trustyai/lm-eval.mdx` | `evaluate_safety/lm_eval.mdx` | 重命名（连字符→下划线） | 1 |
| `ai_applications/trustyai/nemo-guardrails.mdx` | `evaluate_safety/nemo_guardrails.mdx` | 重命名（连字符→下划线） | 1 |
| `ai_applications/ragas.mdx` | `evaluate_safety/ragas.mdx` |  |  |

### Monitor 监控与运维 — `monitor/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `ai_applications/trustyai/tas.mdx` | `monitor/bias_drift.mdx` |  | 1 |
| `training_pipelines/kueue/how_to/monitor_pending_workload.mdx` | `monitor/how_to/monitor_pending_workload.mdx` |  |  |
| `monitoring_ops/index.mdx` | `monitor/index.mdx` |  |  |
| `monitoring_ops/logging_tracing/functions/index.mdx` | `monitor/logging_tracing/functions/index.mdx` |  |  |
| `monitoring_ops/logging_tracing/functions/logging.mdx` | `monitor/logging_tracing/functions/logging.mdx` |  |  |
| `monitoring_ops/logging_tracing/index.mdx` | `monitor/logging_tracing/index.mdx` |  |  |
| `monitoring_ops/logging_tracing/intro.mdx` | `monitor/logging_tracing/intro.mdx` |  |  |
| `monitoring_ops/overview/features.mdx` | `monitor/overview/features.mdx` |  |  |
| `monitoring_ops/overview/index.mdx` | `monitor/overview/index.mdx` |  |  |
| `monitoring_ops/overview/intro.mdx` | `monitor/overview/intro.mdx` |  |  |
| `monitoring_ops/resource_monitoring/functions/index.mdx` | `monitor/resource_monitoring/functions/index.mdx` |  |  |
| `monitoring_ops/resource_monitoring/functions/resource_monitoring.mdx` | `monitor/resource_monitoring/functions/resource_monitoring.mdx` |  |  |
| `monitoring_ops/resource_monitoring/how_to/add_monitor_dashboard.mdx` | `monitor/resource_monitoring/how_to/add_monitor_dashboard.mdx` |  |  |
| `monitoring_ops/resource_monitoring/how_to/index.mdx` | `monitor/resource_monitoring/how_to/index.mdx` |  |  |
| `monitoring_ops/resource_monitoring/index.mdx` | `monitor/resource_monitoring/index.mdx` |  |  |
| `monitoring_ops/resource_monitoring/intro.mdx` | `monitor/resource_monitoring/intro.mdx` |  |  |
| `monitoring_ops/resource_monitoring/troubleshooting/index.mdx` | `monitor/resource_monitoring/troubleshooting/index.mdx` |  |  |
| `monitoring_ops/resource_monitoring/troubleshooting/monitor_dashboard_loading_stuck.mdx` | `monitor/resource_monitoring/troubleshooting/monitor_dashboard_loading_stuck.mdx` |  |  |

### API Reference — `apis/`

| 现有路径 | 新路径 | 备注 | 需改链接 |
|---|---|---|---|
| `apis/index.mdx` | `apis/index.mdx` |  |  |
| `apis/intro.mdx` | `apis/intro.mdx` |  |  |
| `apis/kubernetes_apis/index.mdx` | `apis/kubernetes_apis/index.mdx` |  |  |
| `apis/kubernetes_apis/kubeflow.org/index.mdx` | `apis/kubernetes_apis/kubeflow.org/index.mdx` |  |  |
| `apis/kubernetes_apis/kubeflow.org/workspacekinds.mdx` | `apis/kubernetes_apis/kubeflow.org/workspacekinds.mdx` |  |  |
| `apis/kubernetes_apis/kubeflow.org/workspaces.mdx` | `apis/kubernetes_apis/kubeflow.org/workspaces.mdx` |  |  |
| `apis/kubernetes_apis/manage/amlnamespaces.mdx` | `apis/kubernetes_apis/manage/amlnamespaces.mdx` |  |  |
| `apis/kubernetes_apis/manage/index.mdx` | `apis/kubernetes_apis/manage/index.mdx` |  |  |
| `apis/kubernetes_apis/operator/amlclusters.mdx` | `apis/kubernetes_apis/operator/amlclusters.mdx` |  |  |
| `apis/kubernetes_apis/operator/index.mdx` | `apis/kubernetes_apis/operator/index.mdx` |  |  |
| `apis/kubernetes_apis/serving.kserve.io/clusterservingruntimes.mdx` | `apis/kubernetes_apis/serving.kserve.io/clusterservingruntimes.mdx` |  |  |
| `apis/kubernetes_apis/serving.kserve.io/index.mdx` | `apis/kubernetes_apis/serving.kserve.io/index.mdx` |  |  |
| `apis/kubernetes_apis/serving.kserve.io/inferenceservices.mdx` | `apis/kubernetes_apis/serving.kserve.io/inferenceservices.mdx` |  |  |

### 删除

| 路径 | 原因 |
|---|---|
| `ai_applications/dify/overview/index.mdx` | 删除（overview/ 打平后冗余） |
| `ai_applications/index.mdx` | 删除（pillar 解散） |
| `ai_applications/kagenti/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `ai_applications/llama_stack/overview/index.mdx` | 删除（overview/ 打平后冗余） |
| `data_experiments/index.mdx` | 删除（pillar 解散） |
| `data_experiments/label_studio/overview/index.mdx` | 删除（overview/ 打平后冗余） |
| `data_experiments/mlflow/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `infrastructure_management/index.mdx` | 删除（pillar 解散） |
| `learn/index.mdx` | 删除（pillar 解散） |
| `model_inference/envoy_ai_gateway/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `model_inference/index.mdx` | 删除（pillar 解散） |
| `training_pipelines/data_science_pipelines/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `training_pipelines/index.mdx` | 删除（pillar 解散） |
| `training_pipelines/kubeflow/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `training_pipelines/kuberay/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `training_pipelines/kueue/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |
| `training_pipelines/spark_operator/how_to/index.mdx` | 删除（how_to/ 下的页面已迁往场景章节，该分组页冗余） |

## 4. 需要改写的内容（非纯移动）

### 4.1 组件 `intro.mdx` 标题（19 篇）

19 个组件的 `intro.mdx` 标题目前一律是 `# Introduction`，并列在 `components/` 下无法区分，
需改为组件名（例如 `# Alauda Build of Kueue`）。

### 4.2 打平 `overview/` 子目录（9 项）

`dify` / `llama_stack` / `label_studio` 的 `overview/` 子目录在组件移入 `components/` 后会导致 5 层嵌套，
需打平为组件目录下的平级页面。

### 4.3 新建 index.mdx（17 篇）

**章节级 7 篇**（`plan` `administer` `develop` `train` `deploy` `ai_applications` `evaluate_safety`）——
含 h1、`<Overview />`，以及一段**「本章涉及的组件」导语**，链接到住在其它章节的依赖组件。
这是替代占位页的机制。

另有 5 个章节的 index.mdx 由现有目录继承（`overview` `installation` `upgrade` `apis` `monitor`），
其中 `monitor/index.mdx` 的 h1 需从 `Monitoring & Ops` 改为 `Monitor`。

**分组级 10 篇** —— 按规范每个目录都需要 index.mdx：
`plan/`、`evaluate_safety/`、`develop/how_to/`、`develop/experiment_tracking/`、
`train/quota_scheduling/`、`deploy/how_to/`、`deploy/gateway/`、`administer/how_to/`、
`ai_applications/how_to/`、`monitor/how_to/`。

### 4.5 导航深度校验

新结构最深 4 层（章节 > 模块 > 分组 > 页面），与现状持平，0 处超标。
层数分布：2 层 26 篇、3 层 84 篇、4 层 131 篇。

### 4.4 补齐 Prerequisites（21 篇）

全仓 51 篇 how_to 中仅 30 篇有 Prerequisites，且部分为纯文本未加链接
（如 `kueue/how_to/isvc.mdx` 的「You have installed the Alauda Build of Kueue」）。
迁移后需补齐并统一加上指向组件安装页的链接。

## 5. 跨场景依赖（章节导语需覆盖）

| 场景 | 依赖的组件 | 组件所在章节 | 现有引用数 |
|---|---|---|---|
| Train | Kueue | Train（本章） | 7 → 归零 |
| Develop | Envoy AI Gateway | Deploy | 5 |
| Train | MLflow | Develop | 4 |
| Overview | Dify | Build AI Apps | 3 |
| Upgrade | KServe | Deploy | 2 |
| Administer | MLflow | Develop | 2 |
| Safety | TrustyAI | Evaluate & Safety（本章） | 2 → 归零 |
| Administer | Kagenti | Build AI Apps | 1 |
| Install | KServe | Deploy | 1 |
| Monitor | TrustyAI | Evaluate & Safety | 1 |

## 6. 已定决策

1. **Monitor 独立成章** — 不并入 Administer。监控能力横跨使用者与管理员两个视图
   （`resource_monitoring/how_to/add_monitor_dashboard.mdx` 明确要求切换到 Administrator View，
   而 `logging.mdx` / `resource_monitoring.mdx` 面向推理服务使用者），跨视角的能力应独立为场景。
2. **Feast 归 Develop** — 面向数据科学家的特征库，与 MLflow / Label Studio 同章。
   （RHOAI 将 Feature Store 置于 Administer，此处按国内团队的使用方式选择 Develop。）
3. **Kueue 归 Train** — 连同配额、公平共享、Cohort、RBAC、NPU 配额 5 篇治理页一并移入 `train/quota_scheduling/`。
   理由：引用 Kueue 安装页的 7 处全部来自训练场景；这 5 篇本质是「为训练做的资源治理」而非平台级管理。
   该选择同时消除了最重的一组跨场景依赖（Train→Kueue 7 处归零）。
4. **不设占位页** — 次要场景通过任务页 Prerequisites 的内联链接 + 章节导语指向组件，
   不新增仅含跳转的导航条目（RHOAI 全套文档亦无此类页面）。

## 7. 前置条件与风险

1. **不回合 `release-2.7`** — 本次重构使全部 URL 变更，仅进入 2.8。已发布的 2.7/2.6 由各自 
   release 分支构建，不受影响；若需回合 2.7 则本方案不可行。
2. **版本切换器** — 从 2.7 切到 2.8 时路径失效，需确认切换器对不存在的路径有兜底。
3. **llms.txt 需重新生成** — `grouping_base_path: docs/en` 按一级目录分组，重构后现有分组全部失效。
4. **这是连续第二次重排** — PR #297 刚合并。翻译 sourceSHA、llms.txt、外部引用的成本会叠加，
   建议本方案一次到位，不再分期改动目录结构。


## 8. 二次调整：取消 "How To" 桶

第一版结构保留了旧模块模板的 `how_to/` / `functions/` 分组，评审中暴露三个问题：

1. **章节级 How To 与同级模块语义重叠。** `develop/how_to/` 的 10 篇任务页与同级的
   Workbench、Connections、Experiment Tracking 讲的是同一批工作，读者无法判断
   "Use Kubeflow Notebooks" 应该去 Workbench 还是去 How To。`administer/`、`deploy/`、
   `monitor/`、`ai_applications/` 也各有一个同样的桶，共 5 个。
2. **"How To" 不携带信息。** 该标签只说明体裁不说明内容；RHOAI 的导航节点一律以对象或任务命名
   （Working with connections、Managing resources…），不存在按体裁分组的节点。
3. **单页包装目录。** `deploy/model_compression/how_to/` 只有 index 没有任何页面；另有 6 个
   `how_to/` `functions/` `overview/` `troubleshooting/` 目录只包 1 篇文章。

### 8.1 规则

1. 与模块并列的章节级 `how_to/` 一律拆散，按主题并入既有模块，或新建以任务命名的分组。
2. 模块内的分组：≤4 篇直接打平到模块下；>4 篇保留分组，但重命名为描述性标签。
3. 只含 1 篇文章的包装目录一律打平；空目录删除。
4. 全站不再出现 `How To` 导航标签，目录名同步去掉 `how_to`（URL 与标签一致）。

### 8.2 变更表

| 章节 | 原位置 | 新位置 |
|---|---|---|
| Administer | `administer/how_to/mlflow_workspaces.mdx` | `administer/multi_tenant/`（标题改为 MLflow Workspaces and Access Control） |
| Administer | `administer/how_to/{install_secure_dependencies,enable_secure_profile}.mdx` | `administer/secure_profile/`（新建分组） |
| Administer | `administer/hardware_profile/{functions,how_to}/` | 打平到 `administer/hardware_profile/` |
| Administer | `administer/multi_tenant/functions/` | 打平到 `administer/multi_tenant/` |
| Develop | `develop/how_to/{notebooks,volumes-kserve,tensorboards,upload_models_using_notebook}.mdx` | `develop/workbench/` |
| Develop | `develop/workbench/{overview,how_to}/`、`develop/connections/{overview,how_to}/` | 各自打平到模块下 |
| Develop | `develop/how_to/{create_dspa,pipelines,tekton}.mdx` + `workbench/how_to/run-kubeflow-pipelines-with-elyra.mdx` + `train/how_to/{reusable-pipeline-components,kfp-execution-and-storage}.mdx` | `develop/pipelines/`（新建分组，`pipelines.mdx` 更名 `kubeflow_pipelines.mdx`） |
| Develop | `develop/how_to/{codeflare-sdk-tutorial,run_spark_application}.mdx` | `develop/distributed_workloads/`（新建分组） |
| Develop | `develop/how_to/model-registry.mdx` | `develop/model_registry.mdx`（章节级单页） |
| Train | `train/how_to/` | `train/guides/`（标签本已是 Training Guides，仅对齐目录名） |
| Deploy | `deploy/how_to/isvc.mdx` | `deploy/inference_service/guides/kueue_scheduling.mdx`（标题改为 Schedule Inference Services with Kueue） |
| Deploy | `deploy/inference_service/how_to/`（9 篇） | `deploy/inference_service/guides/`（10 篇，标签 Guides） |
| Deploy | `deploy/inference_service/functions/inference_service.mdx` | 打平到模块下（标题改为 Managing Inference Services） |
| Deploy | `deploy/inference_service/trouble_shooting/` | `deploy/inference_service/troubleshooting/` |
| Deploy | `deploy/model_management/{functions,how_to}/` | 打平到 `deploy/model_management/` |
| Deploy | `deploy/maas/`（仅 1 篇 intro） | `deploy/maas.mdx` |
| Deploy | `deploy/model_compression/how_to/` | 删除（空目录） |
| Build AI Apps | `ai_applications/how_to/`（4 篇） | 章节根，与 Evaluate & Safety 一致 |
| Monitor | `monitor/how_to/monitor_pending_workload.mdx` | `monitor/resource_monitoring/` |
| Monitor | `monitor/{logging_tracing,resource_monitoring}/{functions,how_to,troubleshooting}/` | 各自打平到模块下（`resource_monitoring.mdx` 标题改为 Monitoring Metrics and Views） |

两篇 KFP 通用页（Reusable Pipeline Components、Execution and Storage Behavior）从 Train 移到
Develop > Pipelines：它们讲的是 KFP 本身的能力与行为，不是训练方法；Train 的索引表保留指向它们的跨章链接。

### 8.3 影响

- 删除 21 个 index.mdx，新建 3 个（`develop/pipelines/`、`develop/distributed_workloads/`、
  `administer/secure_profile/`），总页数 252 → 234。
- 二级 How To 节点 5 个 → 0；全站 `how_to` 路径 113 处 → 0（`ExternalSiteLink` 指向 ACP 站点的除外）。
- 相对链接、GitHub raw/tree URL、3 个 e2e 脚本的 assets 路径已同步重写，校验 0 处失效链接、
  0 个目录缺 index.mdx、每个目录的 weight 均为 10 步长无重复。
- §4.3 中"分组级 index.mdx"的清单已被本节取代。

### 8.4 逐篇内容复核后的修正

按"每篇文章的内容 vs 它的位置"复核 §8 结果后修正的 5 项：

| # | 问题 | 处理 |
|---|---|---|
| 1 | doom 的路由是 `**/*.md{,x}`，但 §8 的 weight 重排只扫了 `.mdx`，把 `plan/supported_configurations.md`（weight 10）和 `train/guides/kubeflow-trainer-quick-start.md`（weight 10）撞了 | Plan 恢复 20/30/40，Training Guides 恢复 20…100。这两个目录"10 的空缺"本来就是那个 `.md` 页 |
| 2 | `develop/pipelines/tekton.mdx` 正文讲的是"用 Kueue 的配额管住 Tekton PipelineRun"，标题 *Integrate with Alauda DevOps Pipelines* 让它看起来像 KFP 页 | 改名 *Schedule Alauda DevOps Pipelines with Kueue*，与同源的 `kueue_scheduling.mdx` 对齐 |
| 3 | Kubeflow Notebooks 是 Workbench 的**替代品**（`notebooks.mdx` 自己就这么写），放进 Workbench 模块等于说它是用 Workbench 的方法 | 拆出平级分组 `develop/kubeflow_notebooks/`（Notebooks、Volumes、Tensorboards），index 说明二者关系与 Kubeflow operator 前置 |
| 5 | `upload_models_using_notebook.mdx` 是"往模型仓库传模型"的任务（入链 Deploy 3 + Train 3 + Develop 0），被按"用了 notebook"归到 Workbench | 移到 `deploy/model_management/`，排在 Model Repository 之后 |
| 9 | 两个 index 的 H1 与导航标签不符：Validated Models → `# Inference Guide`，Device Options → `# Device Management` | H1 与标签对齐，并修正一处引用旧名的链接文字 |

仍待决策（本轮未改）：`volumes-kserve.mdx` 后半段其实是 KServe 模型部署，与标题不符，建议拆页；
`deploy/overview/` 的 Introduction 是 Model Management 与 Inference Service 两篇 intro 的逐字拼接，
`monitor/overview/` 同形——场景化导航里章节 index 即 Overview，这两个 Overview 模块建议删除。

### 8.5 拆页与删除 Overview 模块

**`volumes-kserve.mdx` 拆页。** 该页前半是 Kubeflow Volumes（建卷、管卷、挂到 Notebook），
后半 4 节是从 Kubeflow 面板的 KServe Endpoints UI **部署模型**，导航标签 *Use Kubeflow Volumes*
完全盖住了后半段。拆为：

- `develop/kubeflow_notebooks/volumes.mdx` —— 只留卷相关内容，末尾指向下一页；
- `deploy/inference_service/guides/kubeflow_kserve_endpoints.mdx` —— *Deploy Inference Services
  from the Kubeflow Dashboard*，补齐 Introduction / Prerequisites / Verification，
  并说明它创建的是与 CLI、Alauda AI 控制台**同一个** `InferenceService` 对象，只是入口不同。
  排在 Guides 的 CLI 创建页之后。

**删除 `deploy/overview/` 与 `monitor/overview/`。** 场景化导航里章节 index.mdx 就是 Overview，
再挂一个 Overview 模块是旧模块模板的残留，且内容是重复的：

| 页面 | 与谁重复 |
|---|---|
| `deploy/overview/intro.mdx` | 正文 = `model_management/intro.mdx` + `inference_service/intro.mdx` 逐字拼接 |
| `deploy/overview/features.mdx` | `model_repository.mdx` 与 `inference_service.mdx` 的 Advantages / Core Features 的弱化版 |
| `monitor/overview/intro.mdx` | `monitor/index.mdx` 章节导语 |
| `monitor/overview/features.mdx` | `logging.mdx` 的 Core Features 与 `resource_monitoring.mdx` 的 Main Features 的弱化版 |

唯一不重复的一条是 `monitor/overview/intro.mdx` 里的「Hami GPU 面板需 1.4+」，已移入
`resource_monitoring/intro.mdx` 的 Usage Limitations 并补上指向 Hami 页的链接；
Monitor 章节导语补了一句全生命周期可观测性的表述。两个 Overview 模块无任何入链。
