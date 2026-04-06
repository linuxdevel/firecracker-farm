#!/usr/bin/env bash

if [[ -n "${FC_CONFIG_SH_LOADED:-}" ]]; then
  return 0
fi
readonly FC_CONFIG_SH_LOADED=1

# Default platform settings; later tasks can expand or override these safely.
readonly FC_HOST_IP="${FC_HOST_IP:-192.168.1.2}"
readonly FC_DEFAULT_BRIDGE="${FC_DEFAULT_BRIDGE:-vmbr0}"
readonly FC_DEFAULT_DISK_SIZE="${FC_DEFAULT_DISK_SIZE:-20G}"
readonly FC_DEFAULT_MEMORY_MIB="${FC_DEFAULT_MEMORY_MIB:-1024}"
readonly FC_DEFAULT_VCPUS="${FC_DEFAULT_VCPUS:-1}"
readonly FC_RUNTIME_ROOT="${FC_RUNTIME_ROOT:-/var/lib/firecracker}"
readonly FC_LOG_ROOT="${FC_LOG_ROOT:-/var/log/firecracker}"
readonly FC_BINARY_ROOT="${FC_BINARY_ROOT:-/opt/firecracker/bin}"
readonly FC_PREFLIGHT_MIN_FREE_MIB="${FC_PREFLIGHT_MIN_FREE_MIB:-20480}"

# Source persistent host overrides (may set FC_GUEST_USER, FC_SSH_KEY_FILE, etc.)
_fc_host_env="${FC_RUNTIME_ROOT}/host.env"
if [[ -f "$_fc_host_env" ]]; then
  # shellcheck source=/dev/null
  source "$_fc_host_env"
fi
unset _fc_host_env

# Guest identity defaults — used by fc_image_build_template for template
# customization and as fallbacks in fc_image_create_instance_seed.
# fc-create always overrides these with per-VM values via flags or prompts.
readonly FC_GUEST_USER="${FC_GUEST_USER:-$(whoami)}"
readonly FC_SSH_KEY_FILE="${FC_SSH_KEY_FILE:-$HOME/.ssh/authorized_keys}"

# Jailer UID/GID for the Firecracker process after privilege drop.
# Created by fc-install-host as a dedicated system user (firecracker).
# Falls back to 0 (root) if not set — less secure but functional.
readonly FC_JAILER_UID="${FC_JAILER_UID:-0}"
readonly FC_JAILER_GID="${FC_JAILER_GID:-0}"
