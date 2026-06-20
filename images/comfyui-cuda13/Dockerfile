# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=runpod/comfyui:cuda13.0
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="comfyui-cuda13"
LABEL org.opencontainers.image.description="RunPod ComfyUI CUDA 13 runtime layer for comfy_runpod"
LABEL org.opencontainers.image.source="https://github.com/cybergrind/runpod_ghcr_images"

ENV DEBIAN_FRONTEND=noninteractive \
    UV_CACHE_DIR=/opt/uv-cache \
    PIP_CACHE_DIR=/opt/pip-cache \
    HF_HOME=/workspace/.cache/huggingface \
    TORCH_HOME=/workspace/.cache/torch \
    TMPDIR=/workspace/tmp

RUN mkdir -p \
      /workspace/tmp \
      /workspace/.cache/huggingface \
      /workspace/.cache/torch \
      /opt/uv-cache \
      /opt/pip-cache \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      openssh-server \
      python3 \
      python3-pip \
      python3-venv \
      rsync \
      tini \
      unzip \
      zstd \
    && rm -rf /var/lib/apt/lists/*

RUN if ! python3 -m pip install --break-system-packages --no-cache-dir --upgrade pip uv; then \
      curl -LsSf https://astral.sh/uv/install.sh | sh \
      && install -m 0755 /root/.local/bin/uv /usr/local/bin/uv; \
    fi

RUN mkdir -p /workspace /opt/comfyui-runtime

# Entrypoint wrapper: stand up sshd (PUBLIC_KEY, host keys, TCP forwarding) and
# then exec the base image's original launch (/start.sh) so ComfyUI + RunPod
# init still run. SSH PLUS ComfyUI, not instead of it.
COPY entrypoint.sh /opt/comfyui-runtime/entrypoint.sh
RUN chmod +x /opt/comfyui-runtime/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/opt/comfyui-runtime/entrypoint.sh"]
# Setting ENTRYPOINT resets any CMD inherited from the base image to null, so we
# restate the RunPod convention CMD explicitly. It is passed to the entrypoint as
# "$@" and exec'd after sshd starts. The entrypoint also auto-detects /start.sh,
# so it still works if the real base launcher lives at a different path.
CMD ["/start.sh"]
