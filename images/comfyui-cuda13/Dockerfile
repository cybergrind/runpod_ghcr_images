# syntax=docker/dockerfile:1.7

# GHCR-ONLY base: the upstream `runpod/comfyui:cuda13.0` lives on Docker Hub,
# whose UNAUTHENTICATED pull rate-limit (toomanyrequests) breaks pod/image starts.
# CI mirrors that upstream base into GHCR as comfyui-base:cuda13.0 and builds FROM
# the GHCR copy, so this build pulls NOTHING from Docker Hub. The mirror itself is
# done once in the workflow (see build-comfyui-cuda13.yml: "Mirror base to GHCR").
ARG BASE_IMAGE=ghcr.io/cybergrind/runpod_ghcr_images/comfyui-base:cuda13.0
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

# Preserve the real sshd binary and replace /usr/sbin/sshd with a no-op shim.
# The base image's /start.sh runs `/usr/sbin/sshd` inside its setup_ssh(); the
# entrypoint launches /start.sh detached and is itself the authoritative sshd on
# :22. Shadowing /usr/sbin/sshd with a no-op removes any port-22 race between the
# detached base launch and our foreground sshd, deterministically. The entrypoint
# execs the preserved binary at /usr/sbin/sshd.real in the foreground.
RUN if [ -x /usr/sbin/sshd ] && [ ! -e /usr/sbin/sshd.real ]; then \
      cp -a /usr/sbin/sshd /usr/sbin/sshd.real; \
    fi \
    && printf '#!/bin/sh\n# no-op: comfyui-cuda13 entrypoint owns the authoritative sshd on :22\nexit 0\n' > /usr/sbin/sshd \
    && chmod 0755 /usr/sbin/sshd

# Entrypoint wrapper: stand up the volume-independent sshd FIRST (PUBLIC_KEY,
# host keys, TCP forwarding) as the resilient foreground PID 1, and launch the
# base /start.sh detached/best-effort so an empty /workspace can never block the
# container from becoming SSH-reachable. ComfyUI is started later by bin/run.py.
COPY entrypoint.sh /opt/comfyui-runtime/entrypoint.sh
RUN chmod +x /opt/comfyui-runtime/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/opt/comfyui-runtime/entrypoint.sh"]
# Setting ENTRYPOINT resets any CMD inherited from the base image to null, so we
# restate the RunPod convention CMD explicitly. It is passed to the entrypoint as
# "$@" and exec'd after sshd starts. The entrypoint also auto-detects /start.sh,
# so it still works if the real base launcher lives at a different path.
CMD ["/start.sh"]
