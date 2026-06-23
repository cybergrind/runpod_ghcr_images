#!/usr/bin/env bash
# Entrypoint for comfyui-cuda13.
#
# Goal: the container MUST come up SSH-reachable within seconds regardless of
# what is (or is not) on the mounted /workspace network volume. The intended
# operational flow is:
#
#   1. container boots + sshd up FIRST (this script, volume-independent)
#   2. bin/bootstrap.py runs over SSH to populate an empty volume from B2
#   3. bin/run.py starts ComfyUI once the volume is hydrated
#
# We therefore DO NOT exec the base image's /start.sh as PID 1: on an empty
# /workspace it blocks (huge `cp -r /opt/comfyui-baked`, venv build) or aborts
# under its own `set -e`, and because it would be the exec'd PID 1 the container
# never stabilizes and sshd never becomes reachable ("RUNNING but no ports/SSH").
#
# Instead: do the volume-INDEPENDENT SSH setup synchronously, launch the base
# /start.sh DETACHED (best-effort, tolerant of an empty volume), and make sshd
# the resilient foreground PID 1 so the container stays alive and answers on
# port 22 within seconds no matter what /start.sh does.
#
# Idempotent: safe to re-run on container restart.
set -uo pipefail

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# 1. Volume-INDEPENDENT SSH setup (synchronous). RunPod injects the user's
#    public key via $PUBLIC_KEY.
# ---------------------------------------------------------------------------
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -n "${PUBLIC_KEY:-}" ]; then
  # Avoid duplicating the key on container restarts.
  if ! grep -qxF "$PUBLIC_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
  fi
  chmod 600 ~/.ssh/authorized_keys
  log "PUBLIC_KEY installed into ~/.ssh/authorized_keys"
else
  log "PUBLIC_KEY not set; sshd will start but key-based login may be unavailable"
fi

# Host keys + sshd config. ssh-keygen -A is a no-op if host keys already exist.
ssh-keygen -A
mkdir -p /run/sshd
sshd_conf=/etc/ssh/sshd_config.d/00-runpod-direct.conf
mkdir -p /etc/ssh/sshd_config.d
cat > "$sshd_conf" <<'EOF'
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
AllowTcpForwarding yes
GatewayPorts yes
PubkeyAuthentication yes
EOF

# Resolve the real sshd binary. The Dockerfile preserves it at
# /usr/sbin/sshd.real and replaces /usr/sbin/sshd with a no-op shim (see below),
# so the base /start.sh's setup_ssh() cannot race us for port 22. If that
# preservation is absent (e.g. a different base), fall back to the binary on
# PATH so this entrypoint still works.
SSHD_BIN=/usr/sbin/sshd.real
[ -x "$SSHD_BIN" ] || SSHD_BIN=/usr/sbin/sshd

# ---------------------------------------------------------------------------
# 2. Launch the base image's /start.sh DETACHED, best-effort. It performs the
#    base GPU/env init (RunPod env propagation, FileBrowser, Jupyter) and, on a
#    POPULATED volume, the ComfyUI launch. On an EMPTY volume it may block or
#    abort under its own `set -e` — fine: it runs fully decoupled in the
#    background and cannot take down our sshd. Its setup_ssh() invokes
#    /usr/sbin/sshd, which the Dockerfile has replaced with a no-op shim, so it
#    never competes for port 22 and the rest of its init still runs.
#
#    NOTE: we deliberately do NOT auto-launch ComfyUI ourselves from an empty
#    volume — that is bin/run.py's job after bootstrap populates /workspace.
# ---------------------------------------------------------------------------
if [ -f /start.sh ]; then
  log "launching base /start.sh detached (best-effort; logs -> /tmp/start.log)"
  # setsid fully decouples a hang/crash in the base launch from PID 1. All
  # output goes to /tmp so an empty/unwritable /workspace can never wedge it.
  nohup setsid bash /start.sh </dev/null >/tmp/start.log 2>&1 &
  log "base /start.sh detached (pid $!)"
else
  log "no /start.sh found; skipping base launch"
fi

# ---------------------------------------------------------------------------
# 3. sshd as the resilient foreground PID 1. The container stays alive and sshd
#    answers on :22 within seconds regardless of /workspace contents. Because
#    the base /start.sh's sshd is a no-op shim, there is no port-22 race: this
#    is the one and only sshd binding :22.
# ---------------------------------------------------------------------------
log "exec $SSHD_BIN -D -e (resilient foreground PID 1 on :22)"
exec "$SSHD_BIN" -D -e
