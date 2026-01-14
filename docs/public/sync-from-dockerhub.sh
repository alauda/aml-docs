#!/usr/bin/env bash
set -euo pipefail

BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

# ==========================================
# 环境变量配置
# ==========================================
TARGET_REGISTRY="${TARGET_REGISTRY:-}"
TARGET_PROJECT="${TARGET_PROJECT:-}"
TARGET_USER="${TARGET_USER:-}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

# 可选：配置 Docker Hub 的凭证以避免 pull 被限流，非强需求但可以预留
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"

RETRY_MAX=5
RETRY_DELAY=30
SKOPEO_TIMEOUT="120m"

WORK_DIR="/tmp/workbench-images-export-from-hub"

# 全局清理机制 (Trap)
trap 'log "${YELLOW}正在清理临时目录释放空间: ${WORK_DIR}${NC}"; rm -rf "${WORK_DIR}"' EXIT

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
# 通用工具函数
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
  log "${BLUE}登录私有镜像仓库: ${TARGET_REGISTRY}...${NC}"
  # 大部分私有 Harbor 不需要代理，如果需要可以类似原脚本注入 HTTP_PROXY 或者让用户全局声明
  skopeo login -u "$TARGET_USER" -p "$TARGET_PASSWORD" --tls-verify=false "$TARGET_REGISTRY" || {
    log "${RED}私有镜像仓库 ${TARGET_REGISTRY} 登录失败，请检查凭据。${NC}"
    exit 1
  }
}

sync_image() {
  local SRC="$1"
  local DEST
  DEST=$(transform_target_dest "$SRC")

  log "${BLUE}Syncing: ${SRC} -> ${DEST}${NC}"

  # 1. 检查目标仓库是否已有该镜像
  if check_target_image_exists "$DEST"; then
    log "${GREEN}Image exists on target registry. Skipping.${NC}"
    return 0
  fi

  # 2. 如果本地不存在该镜像先进行拉取
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

  # 3. 将单层极大（如 7G）的镜像保存到本地成为 tar 包，避免直接通过内存/管道传输引起的崩溃或超时
  log "${BLUE}Exporting to tarball via nerdctl save...${NC}"
  nerdctl save -o "$TAR_FILE" "$SRC"

  # 4. 从本地 tar 包推送到目标仓库（兼容大容量镜像）
  log "${BLUE}Pushing tarball to target registry via Skopeo...${NC}"
  retry skopeo copy \
    --command-timeout "$SKOPEO_TIMEOUT" \
    --retry-times 3 \
    --dest-tls-verify=false \
    "docker-archive:${TAR_FILE}" "docker://${DEST}"

  log "${GREEN}Successfully synced ${SRC} to ${DEST}${NC}"
  
  # 5. 推送成功后即刻清理以释放大容量的临时磁盘占用
  rm -f "$TAR_FILE"
  return 0
}

main() {
  if [ -z "$TARGET_REGISTRY" ] || [ -z "$TARGET_PROJECT" ] || [ -z "$TARGET_USER" ] || [ -z "$TARGET_PASSWORD" ]; then
    log "${RED}错误: 缺少必要的环境变量。${NC}"
    log "请通过 export 的方式提供相关环境参数:"
    log "  export TARGET_REGISTRY=build-harbor.alauda.cn"
    log "  export TARGET_PROJECT=mlops/workbench-images"
    log "  export TARGET_USER=admin"
    log "  export TARGET_PASSWORD=your_password"
    log "执行示例: ./$0"
    exit 1
  fi

  if [ -n "$DOCKERHUB_USER" ] && [ -n "$DOCKERHUB_PASSWORD" ]; then
    log "${BLUE}登录 DockerHub 以避免拉取限流...${NC}"
    nerdctl login -u "$DOCKERHUB_USER" -p "$DOCKERHUB_PASSWORD" docker.io || true
  fi

  login_target

  log "${BLUE}=== 开始同步 Workbench 镜像至 ${TARGET_REGISTRY}/${TARGET_PROJECT} ===${NC}"
  local TOTAL=${#WORKBENCH_IMAGES[@]}
  local i=0 SRC
  for SRC in "${WORKBENCH_IMAGES[@]}"; do
    i=$((i + 1))
    echo -en "\n[${i}/${TOTAL}] "
    sync_image "$SRC" || {
      log "${RED}同步失败：${SRC}${NC}"
      exit 1
    }
  done
  log "${GREEN}=== 所有镜像同步完成 ===${NC}"
}

main "$@"
