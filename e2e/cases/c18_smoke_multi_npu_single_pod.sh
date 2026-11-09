#!/usr/bin/env bash
# C18 — two torchrun ranks, two NPUs, one Kubernetes Job Pod.
set -euo pipefail
export A5_CASE=C18
export A5_IMAGE="${C18_IMAGE:-10.226.77.76:30002/library/vllm-ascend:v0.23.0.post1-a5-openeuler-c8-c9-c11-20261029-arm64-c11fix2}"
source "$(cd "$(dirname "$0")" && pwd)/../a5-training-job.sh"
