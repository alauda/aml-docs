#!/usr/bin/env bash
# C19 — single-device LLaMA Factory LoRA training; GPU by default.
set -euo pipefail
export TRAINING_CASE=C19
export TRAINING_IMAGE="${C19_IMAGE:-${TRAINING_IMAGE:-}}"
source "$(cd "$(dirname "$0")" && pwd)/../training-smoke-job.sh"
