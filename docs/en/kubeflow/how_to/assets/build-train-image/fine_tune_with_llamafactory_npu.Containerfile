ARG TARGETARCH

# FROM ascend/cann:8.5.0-910b-ubuntu22.04-py3.11
FROM build-harbor.alauda.cn/mlops/cann:8.5.0-910b-ubuntu22.04-py3.11
ARG TARGETARCH

ARG PYTHON_VERSION=3.11
ARG APP_ROOT=/opt/app-root
ENV PYTHON=python${PYTHON_VERSION}

USER 0

RUN /bin/bash <<'EOF'
set -Eeuxo pipefail
if [ "${TARGETARCH}" != "arm64" ]; then
  echo "CANN base image only supports TARGETARCH=arm64, got: ${TARGETARCH}" >&2
  exit 1
fi
EOF

# NOTE: my own install script for apt packages.
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -yq --no-install-recommends \
    git git-lfs unzip curl ffmpeg build-essential pkg-config libjemalloc2 libjemalloc-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/app-root/venv \
    PATH="/opt/app-root/uv:/opt/app-root/venv/bin:${PATH}" \
    UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    UV_HTTP_TIMEOUT=300 \
    UV_NO_CACHE=true \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8

RUN HTTPS_PROXY=http://192.168.144.12:7890 curl -LsSf https://astral.sh/uv/install.sh | HTTPS_PROXY=http://192.168.144.12:7890 UV_INSTALL_DIR="/opt/app-root/uv" sh

RUN echo "HwHiAiUser:x:1000:1001,default" >> /etc/group && \
echo "HwHiAiUser:x:1001:1001::/opt/app-root:/sbin/nologin" >> /etc/passwd && \
chown -R 1001:HwHiAiUser /opt/app-root
USER 1001
WORKDIR /opt/app-root/src

# Install PyTorch (CPU wheels) + torch_npu for Ascend 910B
RUN uv venv --python $PYTHON_VERSION /opt/app-root/venv && \
    uv pip install --no-cache-dir \
        torch==2.6.0 \
        torchvision==0.21.0 \
        torchaudio==2.6.0 && \
    uv pip install --no-cache-dir torch-npu==2.6.0.post5

# Install LLaMA-Factory (without awq extra, which is CUDA-only) and training dependencies
RUN uv pip install --no-cache-dir \
    "llamafactory[metrics,modelscope]" \
    "transformers<=4.51.1" \
    "tokenizers>=0.21.1" \
    "loguru~=0.7.2" \
    "deepspeed~=0.16.9" \
    "mlflow>=3.1"
