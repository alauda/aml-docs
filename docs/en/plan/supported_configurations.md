---
weight: 10
---

# Architecture, Version and Components

This page lists the currently maintained Alauda AI versions in the component matrix: the current release and the most recent Stable release before it.

## x86_64 Architecture

| Components                                   | Type           | Alauda AI v2.3 Stable              | Alauda AI v2.8 Stable            |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x, v4.3.x     | v4.1.x, v4.2.x, v4.3.x, v4.4.x (1)|
| Alauda AI Essentials (2)                     | Cluster Plugin | v2.3.0                             | Removed                          |
| Alauda AI                                    | Operator       | v2.3.0                             | v2.8.1                           |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.7                             | Replaced (3)                     |
| Alauda AI Workbench Operator                 | Operator       | -                                  | v0.2.0                           |
| Alauda Build of KServe                       | Operator       | v0.16.0                            | v0.19.0-1                        |
| Alauda Build of Serving Runtime              | Operator       | -                                  | v1.1.1                           |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.18.4                            | Deprecated (7)                   |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1                       | Deprecated (7)                   |
| Alauda GPU Management                        | Operator       | -                                  | v26.3.3-1                        |
| Alauda Build of HAMi                         | Cluster Plugin | v2.8.1                             | v2.9.0                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.0                            | v1.10.3                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.4                            | v0.18.3                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0-1                           | Replaced                         |
| Alauda Build of LeaderWorkerSet              | Operator       | -                                  | v0.9.0-1                         |
| Alauda Build of JobSet                       | Operator       | -                                  | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.12.4                            | v1.15.0                          |
| MLFlow                                       | Cluster Plugin | v3.1.5                             | Replaced                         |
| MLFlow Operator                              | Operator       | -                                  | v3.13.0                          |
| Kubeflow Base                                | Cluster Plugin | v1.10.14-1                         | Replaced                         |
| Kubeflow Base Operator                       | Operator       | -                                  | v26.3.5                          |
| Kubeflow Pipelines                           | Cluster Plugin | v1.10.13                           | Replaced                         |
| Kubeflow Pipelines Operator                  | Operator       | -                                  | v26.3.5                          |
| Kubeflow Trainer v2                          | Cluster Plugin | v1.10.13                           | Replaced                         |
| Kubeflow Trainer Operator                    | Operator       | -                                  | v26.3.5                          |
| Data Science Pipeline Operator               | Operator       | -                                  | v2.15.1                          |
| Kubeflow Model Registry                      | Operator       | v1.10.13                           | Replaced                         |
| Alauda Build of Kubeflow Model Registry      | Operator       | -                                  | v0.3.8-2                         |
| Alauda Build of Llama Stack                  | Operator       | v0.8.0                             | v0.9.0                           |
| Label Studio                                 | Helm Chart     | v1.21.0-2                          | v1.21.0-2                        |
| Alauda Build of Envoy AI Gateway             | Cluster Plugin | v0.4.1                             | Replaced                         |
| Alauda Build of Envoy AI Gateway             | Operator       | -                                  | v0.6.0-2                         |
| Dify                                         | Helm Chart     | v1.11.4                            | Replaced                         |
| Dify Operator                                | Operator       | -                                  | v1.15.0                          |
| Langflow (4)                                 | Helm Chart     | v1.6.4-1                           | Deprecated                       |
| Evidently                                    | Helm Chart     | v0.7.14-1                          | v0.7.14-1                        |
| Featureform (4)                              | Helm Chart     | v0.12.1-2                          | Deprecated                       |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL (5)                               | Operator       | v4.2.0                             | v4.3.3                           |
| Alauda Cache Service for Redis OSS (5)       | Operator       | -                                  | v5.0.2                           |
| Alauda Build of Authorino (5)                | Operator       | -                                  | v0.26.0-1                        |
| Milvus Operator                              | Helm Chart     | v1.3.5                             | v1.3.5                           |
| Alauda Build of Gitlab (6)                   | Operator       | v18.5.1                            | -                                |
| Alauda Build of Harbor (6)                   | Operator       | -                                  | v2.4.14                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.2-2                         |
| Alauda Build of MCP Lifecycle Operator       | Operator       | -                                  | v0.2.0-1                         |
| Kagenti Operator                             | Operator       | -                                  | v0.3.0-rc.1                      |
| Kagenti UI Operator                          | Operator       | -                                  | v0.6.1                           |

## ARM Architecture


| Components                                   | Type           | Alauda AI v2.3 Stable              | Alauda AI v2.8 Stable            |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x, v4.3.x     | v4.1.x, v4.2.x, v4.3.x, v4.4.x   |
| Alauda AI Essentials                         | Cluster Plugin | v2.3.0                             | Removed                          |
| Alauda AI                                    | Operator       | v2.3.0                             | v2.8.1                           |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.7                             | Replaced                         |
| Alauda AI Workbench Operator                 | Operator       | -                                  | v0.2.0                           |
| Alauda Build of KServe                       | Operator       | v0.16.0                            | v0.19.0-1                        |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.18.4                            | Deprecated (7)                   |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1                       | Deprecated (7)                   |
| Alauda Build of NPU Operator                 | Cluster Plugin | v1.1.3                             | Replaced                         |
| Alauda Build of NPU Operator                 | Operator       | -                                  | v26.6.0                          |
| Alauda Build of HAMi                         | Cluster Plugin | v2.8.1                             | v2.9.0                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.0                            | v1.10.3                          |
| Alauda Build of HAMi Ascend Device Plugin    | Operator       | -                                  | v1.4.0                           |
| Alauda Build of InferNex Bridge              | Operator       | -                                  | v26.6.0                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.4                            | v0.18.3                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0-1                           | Replaced                         |
| Alauda Build of LeaderWorkerSet              | Operator       | -                                  | v0.9.0-1                         |
| Alauda Build of JobSet                       | Operator       | -                                  | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.12.4                            | v1.15.0                          |
| MLFlow                                       | Cluster Plugin | v3.1.5                             | Replaced                         |
| MLFlow Operator                              | Operator       | -                                  | v3.13.0                          |
| Kubeflow Base                                | Cluster Plugin | v1.10.14-1                         | Replaced                         |
| Kubeflow Base Operator                       | Operator       | -                                  | v26.3.5                          |
| Kubeflow Pipelines                           | Cluster Plugin | v1.10.13                           | Replaced                         |
| Kubeflow Pipelines Operator                  | Operator       | -                                  | v26.3.5                          |
| Kubeflow Trainer v2                          | Cluster Plugin | v1.10.13                           | Replaced                         |
| Kubeflow Trainer Operator                    | Operator       | -                                  | v26.3.5                          |
| Data Science Pipeline Operator               | Operator       | -                                  | v2.15.1                          |
| Kubeflow Model Registry                      | Operator       | v1.10.13                           | Replaced                         |
| Alauda Build of Kubeflow Model Registry      | Operator       | -                                  | v0.3.8-2                         |
| Alauda Build of Llama Stack                  | Operator       | v0.8.0                             | v0.9.0                           |
| Label Studio                                 | Helm Chart     | v1.21.0-2                          | v1.21.0-2                        |
| Alauda Build of Envoy AI Gateway             | Cluster Plugin | v0.4.1                             | Replaced                         |
| Alauda Build of Envoy AI Gateway             | Operator       | -                                  | v0.6.0-2                         |
| Dify                                         | Helm Chart     | v1.11.4                            | Replaced                         |
| Dify Operator                                | Operator       | -                                  | v1.15.0                          |
| Langflow                                     | Helm Chart     | v1.6.4-1                           | Deprecated                       |
| Evidently                                    | Helm Chart     | v0.7.14-1                          | v0.7.14-1                        |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL                                   | Operator       | v4.2.0                             | v4.3.3                           |
| Alauda Cache Service for Redis OSS           | Operator       | -                                  | v5.0.2                           |
| Alauda Build of Authorino                    | Operator       | -                                  | v0.26.0-1                        |
| Milvus Operator                              | Helm Chart     | v1.3.5                             | v1.3.5                           |
| Alauda Build of Gitlab                       | Operator       | v18.5.1                            | -                                |
| Alauda Build of Harbor                       | Operator       | -                                  | v2.4.14                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.2-2                         |
| Alauda Build of MCP Lifecycle Operator       | Operator       | -                                  | v0.2.0-1                         |
| Kagenti Operator                             | Operator       | -                                  | v0.3.0-rc.1                      |
| Kagenti UI Operator                          | Operator       | -                                  | v0.6.1                           |

## Notes

(1) **Alauda AI** v2.8 no longer supports **Alauda Container Platform** v4.0.x. **Alauda AI** v2.3.x remains supported until **Alauda Container Platform** v4.0.x reaches end of life.

(2) **Alauda AI Essentials** is removed after **Alauda AI** v2.6.

(3) *Replaced* indicates that the component deployment method has changed; Operator replaces Cluster Plugin or Helm Chart.

(4) **Featureform** and **Langflow** are deprecated and should not be used for new deployments.

(5) **PostgreSQL**, **Alauda Cache Service for Redis OSS**, and **Alauda Build of Authorino** are dependencies of MaaS.

(6) Model storage has changed from GitLab to container registry, and Harbor is recommended for storing models.

(7) **Alauda Build of NVIDIA GPU Device Plugin** and **Alauda Build of DCGM-Exporter** are deprecated, and **Alauda GPU Management** is recommended to replace them.