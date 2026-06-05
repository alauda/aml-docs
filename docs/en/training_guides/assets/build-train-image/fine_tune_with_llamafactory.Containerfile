FROM nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04

RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources && \
sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/ubuntu.sources && \
apt-get update && \
apt-get install -yq software-properties-common && \
add-apt-repository ppa:deadsnakes/ppa && \
apt-get update && \
export DEBIAN_FRONTEND=noninteractive && \
apt-get install -yq --no-install-recommends \
python3.12 python3.12-venv python3.12-dev git git-lfs unzip curl ffmpeg default-libmysqlclient-dev build-essential pkg-config && \
apt clean && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

ENV UV_SYSTEM_PYTHON=1

WORKDIR /opt
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen

ENV PATH=$PATH:/opt/.venv/bin
