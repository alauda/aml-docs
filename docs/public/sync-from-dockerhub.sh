#!/usr/bin/env bash
set -euo pipefail

BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

# ==========================================
# Environment Variable Configuration
# ==========================================
TARGET_REGISTRY="${TARGET_REGISTRY:-}"
TARGET_PROJECT="${TARGET_PROJECT:-}"
TARGET_USER="${TARGET_USER:-}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

# Optional: Configure Docker Hub credentials to avoid pull rate limiting. Not required but recommended.
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"

RETRY_MAX=5
RETRY_DELAY=30
SKOPEO_TIMEOUT="120m"

WORK_DIR="/tmp/workbench-images-export-from-hub"

# Global cleanup mechanism (Trap)
trap 'log "${YELLOW}Cleaning up temporary directory to free space: ${WORK_DIR}${NC}"; rm -rf "${WORK_DIR}"' EXIT

declare -a WORKBENCH_IMAGES=(
  "docker.io/alaudadockerhub/odh-workbench-codeserver-datascience-cpu-py312-ubi9:3.4_ea1-v1.41"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-datascience-cpu-py312-ubi9:3.4_ea1-v1.41"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-minimal-cpu-py312-ubi9:3.4_ea2-v1.42"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-minimal-cuda-py312-ubi9:3.4_ea2-v1.42"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-pytorch-cuda-py312-ubi9:3.4_ea1-v1.41"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-pytorch-llmcompressor-cuda-py312-ubi9:3.4_ea1-v1.41"
  "docker.io/alaudadockerhub/odh-workbench-jupyter-tensorflow-cuda-py312-ubi9:3.4_ea2-v1.42"
)

# ==========================================
# Utility Functions
# ==========================================
log() {
  printf "%b\n" "$1"
}

retry() {
  local max=${RETRY_MAX}
  local delay=${RETRY_DELAY}
  local attempt=1
  local -a cmd=("$@")
  while true; do
    if "${cmd[@]}"; then
      return 0
    else
      if [ "$attempt" -ge "$max" ]; then
        log "${RED}Command failed after ${max} attempts: ${cmd[*]}${NC}"
        return 1
      fi
      log "${YELLOW}Attempt ${attempt} failed. Retrying in ${delay}s...${NC}"
      sleep "$delay"
      delay=$((delay * 2))
      attempt=$((attempt + 1))
    fi
  done
}

extract_image_name() {
  local full_image="$1"
  local without_registry="${full_image#docker.io/alaudadockerhub/}"
  echo "${without_registry//[:\/]/_}"
}

transform_target_dest() {
  local src="$1"
  local path="${src##*/}"
  echo "${TARGET_REGISTRY}/${TARGET_PROJECT}/${path}"
}

check_local_image() {
  local src="$1"
  if nerdctl image inspect "$src" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

check_target_image_exists() {
  local dest="$1"
  if skopeo inspect --tls-verify=false "docker://${dest}" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

login_target() {
  log "${BLUE}Logging in to private registry: ${TARGET_REGISTRY}...${NC}"
  # Most private Harbor registries don't require proxy. If needed, inject HTTP_PROXY similar to original script or let user declare globally
  skopeo login -u "$TARGET_USER" -p "$TARGET_PASSWORD" --tls-verify=false "$TARGET_REGISTRY" || {
    log "${RED}Failed to log in to private registry ${TARGET_REGISTRY}. Please check your credentials.${NC}"
    exit 1
  }
}

sync_image() {
  local SRC="$1"
  local DEST
  DEST=$(transform_target_dest "$SRC")

  log "${BLUE}Syncing: ${SRC} -> ${DEST}${NC}"

  # 1. Check if image already exists in target registry
  if check_target_image_exists "$DEST"; then
    log "${GREEN}Image exists on target registry. Skipping.${NC}"
    return 0
  fi

  # 2. Pull image from DockerHub if not present locally
  if ! check_local_image "$SRC"; then
    log "${BLUE}Pulling original image from DockerHub (nerdctl pull)...${NC}"
    retry nerdctl pull "$SRC"
  else
    log "${GREEN}Image already pulled locally.${NC}"
  fi

  local image_name
  image_name=$(extract_image_name "$SRC")
  local TAR_FILE="${WORK_DIR}/${image_name}.tar"

  mkdir -p "$WORK_DIR"

  # 3. Save large single-layer images (e.g., 7GB) to local tar to avoid memory/pipe transfer crashes or timeouts
  log "${BLUE}Exporting to tarball via nerdctl save...${NC}"
  nerdctl save -o "$TAR_FILE" "$SRC"

  # 4. Push from local tar to target registry (compatible with large images)
  log "${BLUE}Pushing tarball to target registry via Skopeo...${NC}"
  retry skopeo copy \
    --command-timeout "$SKOPEO_TIMEOUT" \
    --retry-times 3 \
    --dest-tls-verify=false \
    "docker-archive:${TAR_FILE}" "docker://${DEST}"

  log "${GREEN}Successfully synced ${SRC} to ${DEST}${NC}"

  # 5. Clean up immediately after successful push to free large temporary disk space
  rm -f "$TAR_FILE"
  return 0
}

main() {
  if [ -z "$TARGET_REGISTRY" ] || [ -z "$TARGET_PROJECT" ] || [ -z "$TARGET_USER" ] || [ -z "$TARGET_PASSWORD" ]; then
    log "${RED}Error: Missing required environment variables.${NC}"
    log "Please provide the following environment parameters via export:"
    log "  export TARGET_REGISTRY=build-harbor.alauda.cn"
    log "  export TARGET_PROJECT=mlops/workbench-images"
    log "  export TARGET_USER=admin"
    log "  export TARGET_PASSWORD=your_password"
    log "Example: ./$0"
    exit 1
  fi

  if [ -n "$DOCKERHUB_USER" ] && [ -n "$DOCKERHUB_PASSWORD" ]; then
    log "${BLUE}Logging in to DockerHub to avoid pull rate limiting...${NC}"
    nerdctl login -u "$DOCKERHUB_USER" -p "$DOCKERHUB_PASSWORD" docker.io || true
  fi

  login_target

  log "${BLUE}=== Starting Workbench image sync to ${TARGET_REGISTRY}/${TARGET_PROJECT} ===${NC}"
  local TOTAL=${#WORKBENCH_IMAGES[@]}
  local i=0 SRC
  for SRC in "${WORKBENCH_IMAGES[@]}"; do
    i=$((i + 1))
    echo -en "\n[${i}/${TOTAL}] "
    sync_image "$SRC" || {
      log "${RED}Sync failed: ${SRC}${NC}"
      exit 1
    }
  done
  log "${GREEN}=== All images synced successfully ===${NC}"
}

main "$@"
