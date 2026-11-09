#!/usr/bin/env bash
# C19 — direct, single-NPU LLaMA Factory LoRA training from the A5 report.
set -euo pipefail
export A5_CASE=C19
export A5_IMAGE="${C19_IMAGE:-10.226.77.76:30002/library/vllm-ascend:v0.26.0rc2-a5}"
source "$(cd "$(dirname "$0")" && pwd)/../a5-training-job.sh"
