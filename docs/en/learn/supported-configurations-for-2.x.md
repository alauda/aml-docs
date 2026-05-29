---
weight: 10
---

# Architecture, Version and Components

This page lists the currently maintained Alauda AI versions in the component matrix: the current release and the most recent Stable release before it.

## x86_64 Architecture

| Components                                   | Type           | Alauda AI v2.3 Stable              | Alauda AI v2.5 Fast              |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x, v4.3.x     | v4.0.x, v4.1.x, v4.2.x, v4.3.x   |
| Alauda AI Essentials                         | Cluster Plugin | v2.3.0                             | v2.5.0                           |
| Alauda AI                                    | Operator       | v2.3.0                             | v2.5.0                           |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.7                             | v0.1.8                           |
| Alauda Build of KServe                       | Operator       | v0.16.0                            | v0.16.1                          |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.18.4                            | v0.18.4                          |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1                       | v4.2.3-413-1                     |
| Alauda Build of HAMi                         | Cluster Plugin | v2.8.1                             | v2.8.3                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.0                            | v1.10.0                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.4                            | v0.17.4                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0-1                           | v0.8.0-1                         |
| Alauda Build of JobSet (1)                   | Operator       | -                                  | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.12.4                            | v1.12.4                          |
| MLFlow                                       | Cluster Plugin | v3.1.5                             | v3.10.0                          |
| Kubeflow Base                                | Cluster Plugin | v1.10.14-1                         | v1.11.0                          |
| Kubeflow Pipelines (2)                       | Cluster Plugin | v1.10.13                           | v1.11.0                          |
| Kubeflow Trainer v2 (1)                      | Cluster Plugin | v1.10.13                           | v1.11.0                          |
| Kubeflow Model Registry                      | Operator       | v1.10.13                           | v0.3.8                           |
| Alauda build of Llama Stack                  | Operator       | v0.8.0                             | v0.9.0                           |
| Label Studio                                 | Helm Charts    | v1.21.0-2                          | v1.21.0-2                        |
| Alauda build of Envoy AI Gateway             | Cluster Plugin | v0.4.1                             | -                                |
| Alauda build of Envoy AI Gateway             | Operator       | -                                  | v0.4.3                           |
| Dify                                         | Helm Charts    | v1.11.4                            | v1.11.4                          |
| Langflow                                     | Helm Charts    | v1.6.4-1                           | v1.6.4-1                         |
| Evidently                                    | Helm Charts    | v0.7.14-1                          | v0.7.14-1                        |
| Featureform (2)                              | Helm Charts    | v0.12.1-2                          | v0.12.1-2                        |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL                                   | Operator       | v4.2.0                             | v4.2.0                           |
| Milvus Operator                              | Cluster Plugin | v1.3.5                             | v1.3.5                           |
| Alauda Build of Gitlab                       | Operator       | v18.5.1                            | v18.5.1                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.1                           |

## ARM Architecture

| Components                                   | Type           | Alauda AI v2.3 Stable              | Alauda AI v2.5 Fast              |
| -------------------------------------------- | -------------- | ---------------------------------- | -------------------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x, v4.3.x     | v4.0.x, v4.1.x, v4.2.x, v4.3.x   |
| Alauda AI Essentials                         | Cluster Plugin | v2.3.0                             | v2.5.0                           |
| Alauda AI                                    | Operator       | v2.3.0                             | v2.5.0                           |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.7                             | v0.1.8                           |
| Alauda Build of KServe                       | Operator       | v0.16.0                            | v0.16.1                          |
| Alauda Build of KubeRay Operator             | Cluster Plugin | v1.6.0                             | v1.6.0                           |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.18.4                            | v0.18.4                          |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                            | v25.8.1                          |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1                       | v4.2.3-413-1                     |
| Alauda Build of NPU Operator (3)             | Cluster Plugin | v1.1.3                             | v1.1.3                           |
| Alauda Build of HAMi                         | Cluster Plugin | v2.8.1                             | v2.8.3                           |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.10.0                            | v1.10.0                          |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.4                            | v0.17.4                          |
| Alauda Build of Kueue                        | Cluster Plugin | v0.17.0                            | v0.17.0                          |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0-1                           | v0.8.0-1                         |
| Alauda Build of JobSet (1)                   | Operator       | -                                  | v0.12.0                          |
| Volcano                                      | Cluster Plugin | v1.12.4                            | v1.12.4                          |
| MLFlow                                       | Cluster Plugin | v3.1.5                             | v3.10.0                          |
| Kubeflow Base                                | Cluster Plugin | v1.10.14-1                         | v1.11.0                          |
| Kubeflow Trainer v2 (1)                      | Cluster Plugin | v1.10.13                           | v1.11.0                          |
| Kubeflow Model Registry                      | Operator       | v1.10.13                           | v0.3.8                           |
| Alauda build of Llama Stack                  | Operator       | v0.8.0                             | v0.9.0                           |
| Label Studio                                 | Helm Charts    | v1.21.0-2                          | v1.21.0-2                        |
| Alauda build of Envoy AI Gateway             | Cluster Plugin | v0.4.1                             | -                                |
| Alauda build of Envoy AI Gateway             | Operator       | -                                  | v0.4.3                           |
| Dify                                         | Helm Charts    | v1.11.4                            | v1.11.4                          |
| Langflow                                     | Helm Charts    | v1.6.4-1                           | v1.6.4-1                         |
| Evidently                                    | Helm Charts    | v0.7.14-1                          | v0.7.14-1                        |
| Alauda Build of Feast                        | Operator       | v0.61.1                            | v0.61.1                          |
| Knative Operator                             | Operator       | v1.19.3-260213                     | v1.19.3-260213                   |
| PostgreSQL                                   | Operator       | v4.2.0                             | v4.2.0                           |
| Milvus Operator                              | Cluster Plugin | v1.3.5                             | v1.3.5                           |
| Alauda Build of Gitlab                       | Operator       | v18.5.1                            | v18.5.1                          |
| Alauda Build of TrustyAI                     | Operator       | v3.4.1                             | v3.4.1                           |

## Notes

(1) 'Kubeflow Trainer v2' and 'Alauda Build of JobSet' require Alauda Container Platform 4.1.x or later

(2) 'Featureform' and 'Kubeflow Pipelines' are only supported on x86_64 architecture

(3) 'Alauda Build of NPU Operator' is only supported on ARM architecture

(4) 'Alauda build of Envoy AI Gateway' has been refactored from a Cluster Plugin to an Operator in Alauda AI v2.5
