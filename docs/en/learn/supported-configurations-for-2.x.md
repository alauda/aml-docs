---
weight: 10
---

# Architecture, Version and Components

## x86_64 Architecture

| Alauda AI Version                            |                | Alauda AI-v2.0         | Alauda AI-v2.1         | Alauda AI-v2.2         | Alauda AI-v2.3         |
| -------------------------------------------- | -------------- | ---------------------- | ---------------------- | ---------------------- | ---------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x, v4.3.x |
| **Components**                               | **Type**       | **Version**            | **Version**            | **Version**            | **Version**            |
| Alauda AI Essentials                         | Cluster Plugin | v2.0.1                 | v2.1.0                 | v2.2.0                 | v2.3.0                 |
| Alauda AI                                    | Operator       | v2.0.1                 | v2.1.0                 | v2.2.0                 | v2.3.0                 |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.5                 | v0.1.6                 | v0.1.6                 | v0.1.7                 |
| Alauda Build of KServe                       | Cluster Plugin | v2.0.1                 | v2.0.1                 | -                      | -                      |
| Alauda Build of KServe                       | Operator       | -                      | -                      | v0.16.0                | v0.16.0                |
| Alauda Build of KubeRay Operator             | Cluster Plugin | -                      | -                      | -                      | v1.6.0                 |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.17.4                | v0.17.4                | v0.18.2                | v0.18.4                |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                | v25.8.1                | v25.8.1                | v25.8.1                |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1           | v4.2.3-413-1           | v4.2.3-413-1           | v4.2.3-413-1           |
| Alauda Build of HAMi                         | Cluster Plugin | v2.7.1                 | v2.7.1                 | v2.7.1                 | v2.8.1                 |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.5.0                 | v1.5.0                 | v1.5.0                 | v1.10.0                |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.3-1              | v0.17.3-1              | v0.17.3-1              | v0.17.4                |
| Alauda Build of Kueue                        | Cluster Plugin | v0.16.0                | v0.16.0                | v0.17.0                | v0.17.0                |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0                 | v0.8.0                 | v0.8.0-1               | v0.8.0-1               |
| Volcano                                      | Cluster Plugin | v1.12.3                | v1.12.3                | v1.12.4                | v1.12.4                |
| MLFlow                                       | Cluster Plugin | v3.1.4                 | v3.1.4                 | v3.1.5                 | v3.1.5                 |
| Kubeflow Base                                | Cluster Plugin | v1.10.10               | v1.10.10               | v1.10.13               | v1.10.14-1             |
| Kubeflow Pipelines (3)                       | Cluster Plugin | v1.10.9                | v1.10.9                | v1.10.13               | v1.10.13               |
| Kubeflow Trainer v2 (1)                      | Cluster Plugin | v1.10.10               | v1.10.10               | v1.10.13               | v1.10.13               |
| Kubeflow Model Registry (2)                  | Helm Charts    | v1.10.10               | -                      | -                      | -                      |
| Kubeflow Model Registry                      | Operator       | -                      | v1.10.11               | v1.10.13               | v1.10.13               |
| Alauda build of Llama Stack                  | Operator       | v0.7.0                 | v0.7.0                 | v0.8.0                 | v0.8.0                 |
| Label Studio                                 | Helm Charts    | v1.21.0-2              | v1.21.0-2              | v1.21.0-2              | v1.21.0-2              |
| Alauda build of Envoy AI Gateway             | Cluster Plugin | v0.4.0                 | v0.4.1                 | v0.4.1                 | v0.4.1                 |
| Dify                                         | Helm Charts    | v1.11.4                | v1.11.4                | v1.11.4                | v1.11.4                |
| Langflow                                     | Helm Charts    | v1.6.4-1               | v1.6.4-1               | v1.6.4-1               | v1.6.4-1               |
| Evidently                                    | Helm Charts    | v0.7.14-1              | v0.7.14-1              | v0.7.14-1              | v0.7.14-1              |
| Featureform (3)                              | Helm Charts    | v0.12.1-2              | v0.12.1-2              | v0.12.1-2              | v0.12.1-2              |
| Alauda Build of Feast                        | Operator       | -                      | -                      | -                      | v0.61.1                |
| Knative Operator                             | Operator       | v1.19.3-260213         | v1.19.3-260213         | v1.19.3-260213         | v1.19.3-260213         |
| PostgreSQL                                   | Operator       | v4.2.0                 | v4.2.0                 | v4.2.0                 | v4.2.0                 |
| Milvus Operator                              | Cluster Plugin | v1.3.5                 | v1.3.5                 | v1.3.5                 | v1.3.5                 |
| Alauda Build of Gitlab                       | Operator       | v18.2.0                | v18.2.0                | v18.5.1                | v18.5.1                |
| Alauda Build of TrustyAI                     | Operator       | -                      | v3.4.0                 | v3.4.1                 | v3.4.1                 |

## ARM Architecture

| Alauda AI Version                            |                | Alauda AI-v2.0         | Alauda AI-v2.1         | Alauda AI-v2.2         | Alauda AI-v2.3         |
| -------------------------------------------- | -------------- | ---------------------- | ---------------------- | ---------------------- | ---------------------- |
| Alauda Container Platform Supported Versions |                | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x | v4.0.x, v4.1.x, v4.2.x, v4.3.x |
| **Components**                               | **Type**       | **Version**            | **Version**            | **Version**            | **Version**            |
| Alauda AI Essentials                         | Cluster Plugin | v2.0.1                 | v2.1.0                 | v2.2.0                 | v2.3.0                 |
| Alauda AI                                    | Operator       | v2.0.1                 | v2.1.0                 | v2.2.0                 | v2.3.0                 |
| Alauda AI Workbench                          | Cluster Plugin | v0.1.5                 | v0.1.6                 | v0.1.6                 | v0.1.7                 |
| Alauda Build of KServe                       | Cluster Plugin | v2.0.1                 | v2.0.1                 | -                      | -                      |
| Alauda Build of KServe                       | Operator       | -                      | -                      | v0.16.0                | v0.16.0                |
| Alauda Build of KubeRay Operator             | Cluster Plugin | -                      | -                      | -                      | v1.6.0                 |
| Alauda Build of NVIDIA GPU Device Plugin     | Cluster Plugin | v0.17.4                | v0.17.4                | v0.18.2                | v0.18.4                |
| Alauda Build of NVIDIA DRA Driver for GPUs   | Cluster Plugin | v25.8.1                | v25.8.1                | v25.8.1                | v25.8.1                |
| Alauda Build of DCGM-Exporter                | Cluster Plugin | v4.2.3-413-1           | v4.2.3-413-1           | v4.2.3-413-1           | v4.2.3-413-1           |
| Alauda Build of NPU Operator (4)             | Cluster Plugin | v1.1.2                 | v1.1.2                 | v1.1.3                 | v1.1.3                 |
| Alauda Build of HAMi                         | Cluster Plugin | v2.7.1                 | v2.7.1                 | v2.7.1                 | v2.8.1                 |
| Alauda Build of HAMi-WebUI                   | Cluster Plugin | v1.5.0                 | v1.5.0                 | v1.5.0                 | v1.10.0                |
| Alauda Build of Node Feature Discovery       | Cluster Plugin | v0.17.3-1              | v0.17.3-1              | v0.17.3-1              | v0.17.4                |
| Alauda Build of Kueue                        | Cluster Plugin | v0.16.0                | v0.16.0                | v0.17.0                | v0.17.0                |
| Alauda Build of LeaderWorkerSet              | Cluster Plugin | v0.8.0                 | v0.8.0                 | v0.8.0-1               | v0.8.0-1               |
| Volcano                                      | Cluster Plugin | v1.12.3                | v1.12.3                | v1.12.4                | v1.12.4                |
| MLFlow                                       | Cluster Plugin | v3.1.4                 | v3.1.4                 | v3.1.5                 | v3.1.5                 |
| Kubeflow Base                                | Cluster Plugin | v1.10.10               | v1.10.10               | v1.10.13               | v1.10.14-1             |
| Kubeflow Trainer v2 (1)                      | Cluster Plugin | v1.10.10               | v1.10.10               | v1.10.13               | v1.10.13               |
| Kubeflow Model Registry (2)                  | Helm Charts    | v1.10.10               | -                      | -                      | -                      |
| Kubeflow Model Registry                      | Operator       | -                      | v1.10.11               | v1.10.13               | v1.10.13               |
| Alauda build of Llama Stack                  | Operator       | v0.7.0                 | v0.7.0                 | v0.8.0                 | v0.8.0                 |
| Label Studio                                 | Helm Charts    | v1.21.0-2              | v1.21.0-2              | v1.21.0-2              | v1.21.0-2              |
| Alauda build of Envoy AI Gateway             | Cluster Plugin | v0.4.0                 | v0.4.1                 | v0.4.1                 | v0.4.1                 |
| Dify                                         | Helm Charts    | v1.11.4                | v1.11.4                | v1.11.4                | v1.11.4                |
| Langflow                                     | Helm Charts    | v1.6.4-1               | v1.6.4-1               | v1.6.4-1               | v1.6.4-1               |
| Evidently                                    | Helm Charts    | v0.7.14-1              | v0.7.14-1              | v0.7.14-1              | v0.7.14-1              |
| Alauda Build of Feast                        | Operator       | -                      | -                      | -                      | v0.61.1                |
| Knative Operator                             | Operator       | v1.19.3-260213         | v1.19.3-260213         | v1.19.3-260213         | v1.19.3-260213         |
| PostgreSQL                                   | Operator       | v4.2.0                 | v4.2.0                 | v4.2.0                 | v4.2.0                 |
| Milvus Operator                              | Cluster Plugin | v1.3.5                 | v1.3.5                 | v1.3.5                 | v1.3.5                 |
| Alauda Build of Gitlab                       | Operator       | v18.2.0                | v18.2.0                | v18.5.1                | v18.5.1                |
| Alauda Build of TrustyAI                     | Operator       | -                      | v3.4.0                 | v3.4.1                 | v3.4.1                 |

## Notes

(1) 'Kubeflow Trainer v2' requires Alauda Container Platform 4.1.x or later

(2) 'Kubeflow Model Registry' has been refactored from a Helm Charts (v2.0) to an Operator (v2.1)

(3) 'Featureform' and 'Kubeflow Pipelines' are only supported on x86_64 architecture

(4) 'Alauda Build of NPU Operator' is only supported on ARM architecture

(5) 'Alauda Build of KServe' has been refactored from a Cluster Plugin (v2.1) to an Operator (v2.2)
