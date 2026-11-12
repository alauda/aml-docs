---
weight: 10
---

# Architecture, Version and Components

This page lists the currently maintained Alauda AI Platform versions in the component matrix: the current release and the most recent Stable release before it.

## x86_64 Architecture

| Components                                   | Type           | Alauda AI Platform v2.8 Stable     | Alauda AI Platform v2.9 Fast      |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.1.x, v4.2.x, v4.3.x, v4.4.x     | v4.1.x, v4.2.x, v4.3.x, v4.4.x   |
| Alauda AI Platform (1)                       | Operator       | v2.8.1                             | v2.9.0                           |
| Alauda AI Workbench Operator                 | Operator       | v0.2.0                             | v0.2.0                           |
| Alauda AI Platform Inference Management (1)  | Operator       | v0.19.0-2                          | v0.20.0-1                        |
| Alauda AI Platform Serving Runtime (1)       | Operator       | v1.1.1                             | v1.2.2                           |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda GPU Management                        | Operator       | v26.3.3-1                          | v26.3.3-1                        |
| Alauda Build of HAMi                         | Cluster Plugin | v2.9.0                             | v2.9.0                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.3                            | v1.10.3                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.18.3                            | v0.18.3                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Operator       | v0.9.0-1                           | v0.9.0-1                         |
| Alauda Build of JobSet                       | Operator       | v0.12.0                            | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.12.4                            | v1.15.0                          |
| MLFlow Operator                              | Operator       | v3.13.0                            | v3.13.0                          |
| Kubeflow Base Operator                       | Operator       | v26.3.5                            | v26.3.5                          |
| Kubeflow Pipelines Operator                  | Operator       | v26.3.5                            | v26.3.5                          |
| Kubeflow Trainer Operator                    | Operator       | v26.3.5                            | v26.3.5                          |
| Data Science Pipeline Operator               | Operator       | v2.15.1                            | v2.15.1                          |
| Alauda Build of Kubeflow Model Registry      | Operator       | v0.3.8-2                           | v0.3.8-2                         |
| Alauda Build of Llama Stack (2)              | Operator       | v0.9.0                             | Deprecated                       |
| Label Studio                                 | Helm Chart     | v1.21.0-2                          | v1.21.0-2                        |
| Alauda AI Platform Gateway                   | Operator       | v0.6.0-2                           | v1.1.0-1                         |
| Dify Operator                                | Operator       | v1.15.0                            | v1.15.0                          |
| Evidently                                    | Helm Chart     | v0.7.14-1                          | v0.7.14-1                        |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL                                   | Operator       | v4.2.0                             | v4.3.3                           |
| Alauda Cache Service for Redis OSS           | Operator       | v5.0.2                             | v5.0.2                           |
| Alauda Build of Authorino                    | Operator       | v0.26.0-1                          | v0.26.0-1                        |
| Milvus Operator                              | Helm Chart     | v1.3.5                             | v1.3.5                           |
| Alauda Build of Harbor                       | Operator       | v2.4.14                            | v2.4.14                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.2-2                         |
| Alauda Build of MCP Lifecycle Operator       | Operator       | v0.2.0-1                           | v0.2.0-1                         |
| Kagenti Operator (2)                         | Operator       | v0.3.0-rc.1                        | Deprecated                       |
| Kagenti UI Operator (2)                      | Operator       | v0.6.1                             | Deprecated                       |

## ARM Architecture


| Components                                   | Type           | Alauda AI Platform v2.8 Stable     | Alauda AI Platform v2.9 Fast      |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.1.x, v4.2.x, v4.3.x, v4.4.x     | v4.1.x, v4.2.x, v4.3.x, v4.4.x   |
| Alauda AI Platform (1)                       | Operator       | v2.8.1                             | v2.9.0                           |
| Alauda AI Workbench Operator                 | Operator       | v0.2.0                             | v0.2.0                           |
| Alauda AI Platform Inference Management (1)  | Operator       | v0.19.0-2                          | v0.20.0-1                        |
| Alauda AI Platform NPU Serving Runtime (3)   | Operator       | -                                  | v1.0.0                           |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda Build of NPU Operator                 | Operator       | v26.6.0                            | v26.6.0                          |
| Alauda Build of HAMi                         | Cluster Plugin | v2.9.0                             | v2.9.0                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.0                            | v1.10.3                          |
| Alauda Build of HAMi Ascend Device Plugin    | Operator       | v1.4.0                             | v1.4.0                           |
| Alauda Build of InferNex Bridge              | Operator       | v26.6.0                            | v26.6.0                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.18.3                            | v0.18.3                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Operator       | v0.9.0-1                           | v0.9.0-1                         |
| Alauda Build of JobSet                       | Operator       | v0.12.0                            | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.15.0                            | v1.15.0                          |
| MLFlow Operator                              | Operator       | v3.13.0                            | v3.13.0                          |
| Kubeflow Base Operator                       | Operator       | v26.3.5                            | v26.3.5                          |
| Kubeflow Pipelines Operator                  | Operator       | v26.3.5                            | v26.3.5                          |
| Kubeflow Trainer Operator                    | Operator       | v26.3.5                            | v26.3.5                          |
| Data Science Pipeline Operator               | Operator       | v2.15.1                            | v2.15.1                          |
| Alauda Build of Kubeflow Model Registry      | Operator       | v0.3.8-2                           | v0.3.8-2                         |
| Alauda Build of Llama Stack (2)              | Operator       | v0.9.0                             | Deprecated                       |
| Label Studio                                 | Helm Chart     | v1.21.0-2                          | v1.21.0-2                        |
| Alauda AI Platform Gateway                   | Operator       | v0.6.0-2                           | v1.1.0-1                         |
| Dify Operator                                | Operator       | v1.15.0                            | v1.15.0                          |
| Evidently                                    | Helm Chart     | v0.7.14-1                          | v0.7.14-1                        |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL                                   | Operator       | v4.2.0                             | v4.3.3                           |
| Alauda Cache Service for Redis OSS           | Operator       | v5.0.2                             | v5.0.2                           |
| Alauda Build of Authorino                    | Operator       | v0.26.0-1                          | v0.26.0-1                        |
| Milvus Operator                              | Helm Chart     | v1.3.5                             | v1.3.5                           |
| Alauda Build of Harbor                       | Operator       | v2.4.14                            | v2.4.14                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.2-2                         |
| Alauda Build of MCP Lifecycle Operator       | Operator       | v0.2.0-1                           | v0.2.0-1                         |
| Kagenti Operator (2)                         | Operator       | v0.3.0-rc.1                        | Deprecated                       |
| Kagenti UI Operator (2)                      | Operator       | v0.6.1                             | Deprecated                       |

## Notes

1. **Renamed components:** The following names are used in the tables. The previous names are shown for reference:
   - Alauda AI → **Alauda AI Platform**
   - Alauda Build of KServe → **Alauda AI Platform Inference Management**
   - Alauda Build of Serving Runtime → **Alauda AI Platform Serving Runtime**
   - Alauda Build of AI Gateway → **Alauda AI Platform Gateway**
2. **Deprecated in Alauda AI Platform v2.9 Fast:** Alauda Build of Llama Stack, Kagenti Operator, and Kagenti UI Operator are deprecated and are not recommended for new deployments. Llama Stack is no longer managed by `AmlCluster`; consider [Ogx](https://github.com/ogx-ai/ogx) as an alternative.
3. **New component in Alauda AI Platform v2.9 Fast:** Alauda AI Platform NPU Serving Runtime includes vLLM-Ascend `v0.23.0` for inference workloads on Ascend chips.

Alauda AI Platform 2.8 does not support ACP 4.0.x. Alauda AI Platform 2.9.0 Fast supports new installations only; upgrades from previous releases are not supported.
