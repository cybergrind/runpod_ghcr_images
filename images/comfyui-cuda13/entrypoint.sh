#!/usr/bin/env bash
# Entrypoint for comfyui-cuda13.
#
# Goal: provide FULL direct SSH (interactive shell + scp + TCP port-forwarding)
# *in addition to* the base image's normal ComfyUI / RunPod startup. RunPod's
# default web terminal does not give you real sshd, so we stand one up here.
#
# This script is intentionally idempotent: it is safe to re-run on container
# restart, and it never aborts the base launch just because SSH setup hiccups.
set -uo pipefail

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# 1. Authorized keys: RunPod injects the user's public key via $PUBLIC_KEY.
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

# ---------------------------------------------------------------------------
# 2. Host keys + sshd. ssh-keygen -A is a no-op if host keys already exist.
#    Enable TCP forwarding / gateway ports so port-forwarding works.
# ---------------------------------------------------------------------------
ssh-keygen -A
mkdir -p /run/sshd
# Ensure forwarding features are on regardless of base sshd_config defaults.
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

# Start sshd in the background (daemonized). -e logs to stderr for pod logs.
if /usr/sbin/sshd; then
  log "sshd started on port 22 (scp + TCP port-forwarding enabled)"
else
  log "WARNING: sshd failed to start; continuing with base launch anyway"
fi

# ---------------------------------------------------------------------------
# 3. Hand off to the base image's original launch so ComfyUI + RunPod init run.
#    RunPod base images conventionally use CMD ["/start.sh"]. We exec it when
#    present so this container behaves exactly like the unpatched base, plus SSH.
#    Fallback: if no /start.sh, exec whatever args were passed (the inherited
#    CMD), or drop to an interactive shell as a last resort.
# ---------------------------------------------------------------------------
if [ -x /start.sh ]; then
  log "exec /start.sh (base ComfyUI/RunPod launch)"
  exec /start.sh "$@"
elif [ -f /start.sh ]; then
  log "exec bash /start.sh (base ComfyUI/RunPod launch)"
  exec bash /start.sh "$@"
elif [ "$#" -gt 0 ]; then
  log "exec inherited CMD: $*"
  exec "$@"
else
  log "no /start.sh and no CMD args; dropping to interactive bash"
  exec /bin/bash
fi
