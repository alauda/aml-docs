#!/usr/bin/env bash
# C18 — two distributed training ranks inside one Pod; GPU by default.
set -euo pipefail
export TRAINING_CASE=C18
export TRAINING_IMAGE="${C18_IMAGE:-${TRAINING_IMAGE:-}}"
source "$(cd "$(dirname "$0")" && pwd)/../training-smoke-job.sh"
