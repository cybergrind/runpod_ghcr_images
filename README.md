# runpod_ghcr_images

Container images used by the `comfy_runpod` RunPod workflow.

The first image is a thin operational layer over RunPod's CUDA 13 ComfyUI base:

```text
ghcr.io/cybergrind/runpod_ghcr_images/comfyui-cuda13:latest
```

## Images

### `comfyui-cuda13`

Path: `images/comfyui-cuda13/`

Default parent:

```dockerfile
ARG BASE_IMAGE=runpod/comfyui:cuda13.0
FROM ${BASE_IMAGE}
```

The parent is configurable because we may later switch to a lower-level CUDA
base such as `nvidia/cuda:13.3.0-cudnn-runtime-ubuntu22.04`.

I did not find a clearly official NVIDIA CUDA base on GHCR. NVIDIA's maintained
CUDA images are published on Docker Hub/NGC. A GHCR-only Ubuntu parent is
possible, but it would make us own CUDA, Python, ComfyUI, PyTorch, and GPU
dependency installation.

This image intentionally does not bake in checkpoints, LoRAs, VAEs, or text
encoders. Large model files should live in object storage and be hydrated into a
RunPod network volume or local cache.

## Build Locally

```bash
docker build \
  -f images/comfyui-cuda13/Dockerfile \
  -t ghcr.io/cybergrind/runpod_ghcr_images/comfyui-cuda13:local \
  images/comfyui-cuda13
```

Override the parent image:

```bash
docker build \
  --build-arg BASE_IMAGE=nvidia/cuda:13.3.0-cudnn-runtime-ubuntu22.04 \
  -f images/comfyui-cuda13/Dockerfile \
  -t ghcr.io/cybergrind/runpod_ghcr_images/comfyui-cuda13:cuda-runtime \
  images/comfyui-cuda13
```

## Publish

Push to `main`, or run the `Build comfyui-cuda13` workflow manually.

The workflow publishes:

- `latest`
- `main`
- the short commit SHA

If the GHCR package is private after the first push, change visibility in the
GitHub package settings or configure RunPod registry credentials.
