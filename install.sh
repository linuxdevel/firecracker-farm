#!/usr/bin/env bash
# install.sh — Install firecracker-farm on a Linux KVM host.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- --guest-user myuser --ssh-key-file /home/myuser/.ssh/authorized_keys
#   curl -fsSL ... | sudo bash -s -- --version v1.0.0
#
set -euo pipefail

readonly FC_FARM_REPO="linuxdevel/firecracker-farm"
readonly FC_FARM_INSTALL_DIR="/opt/firecracker-farm"
readonly FC_FARM_BIN_LINK_DIR="/usr/local/bin"

log()   { printf '%s\n' "$*" >&2; }
info()  { log "INFO: $*"; }
error() { log "ERROR: $*"; }
ok()    { log "PASS: $*"; }
warn()  { log "WARN: $*"; }

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Install firecracker-farm tools and Firecracker runtime on a Linux host with KVM support.

Options:
  --version TAG        Install a specific release (default: latest)
  --guest-user USER    Username for VM guests (default: operator username)
  --ssh-key-file PATH  SSH public key file (default: ~/.ssh/authorized_keys)
  -h, --help           Show this help text

Examples:
  # Install latest, auto-detect user
  curl -fsSL https://raw.githubusercontent.com/$FC_FARM_REPO/main/install.sh | sudo bash

  # Install with explicit user and key
  curl -fsSL ... | sudo bash -s -- --guest-user myuser --ssh-key-file /home/myuser/.ssh/authorized_keys

  # Pin a version
  curl -fsSL ... | sudo bash -s -- --version v1.0.0
EOF
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "this script must be run as root (use sudo)"
    exit 1
  fi
}

require_command() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "required command not found: $cmd"
    exit 1
  fi
}

ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  info "Installing jq (required for version resolution)"
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends jq >/dev/null
}

resolve_latest_version() {
  local version
  info "Resolving latest release from GitHub"
  version=$(curl -fsSL "https://api.github.com/repos/${FC_FARM_REPO}/releases/latest" | jq -er '.tag_name') || {
    error "unable to resolve latest release from GitHub"
    error "check https://github.com/${FC_FARM_REPO}/releases"
    exit 1
  }
  printf '%s\n' "$version"
}

download_and_extract() {
  local version=$1
  local tarball_name="firecracker-farm-${version}.tar.gz"
  local download_url="https://github.com/${FC_FARM_REPO}/releases/download/${version}/${tarball_name}"
  local tmpdir

  tmpdir=$(mktemp -d)

  info "Downloading firecracker-farm ${version}"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/$tarball_name" "$download_url"; then
    error "download failed: $download_url"
    error "check that release ${version} exists at https://github.com/${FC_FARM_REPO}/releases"
    rm -rf "$tmpdir"
    exit 1
  fi

  info "Installing to ${FC_FARM_INSTALL_DIR}"
  rm -rf "$FC_FARM_INSTALL_DIR"
  mkdir -p "$FC_FARM_INSTALL_DIR"
  tar -xzf "$tmpdir/$tarball_name" -C "$FC_FARM_INSTALL_DIR" --strip-components=1

  rm -rf "$tmpdir"
  ok "Extracted firecracker-farm ${version} to ${FC_FARM_INSTALL_DIR}"
}

create_symlinks() {
  local cmd_path cmd_name

  mkdir -p "$FC_FARM_BIN_LINK_DIR"

  for cmd_path in "$FC_FARM_INSTALL_DIR"/bin/fc-*; do
    [[ -f "$cmd_path" ]] || continue
    cmd_name=$(basename -- "$cmd_path")
    ln -sf "$cmd_path" "${FC_FARM_BIN_LINK_DIR}/${cmd_name}"
  done

  ok "Created symlinks in ${FC_FARM_BIN_LINK_DIR}"
}

run_host_install() {
  local guest_user=$1
  local ssh_key_file=$2
  local install_args=()

  if [[ -n "$guest_user" ]]; then
    install_args+=(--guest-user "$guest_user")
  fi
  if [[ -n "$ssh_key_file" ]]; then
    install_args+=(--ssh-key-file "$ssh_key_file")
  fi

  info "Running fc-install-host to set up Firecracker runtime"
  bash "$FC_FARM_INSTALL_DIR/bin/fc-install-host" "${install_args[@]}"
}

main() {
  local version=
  local guest_user=
  local ssh_key_file=

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || { error "--version requires a value"; exit 1; }
        version=$2
        shift 2
        ;;
      --guest-user)
        [[ $# -ge 2 ]] || { error "--guest-user requires a value"; exit 1; }
        guest_user=$2
        shift 2
        ;;
      --ssh-key-file)
        [[ $# -ge 2 ]] || { error "--ssh-key-file requires a value"; exit 1; }
        ssh_key_file=$2
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
  done

  require_root
  require_command curl
  require_command tar
  ensure_jq

  if [[ -z "$version" ]]; then
    version=$(resolve_latest_version)
  fi
  # Normalize to v-prefix
  if [[ "$version" != v* ]]; then
    version="v${version}"
  fi

  info "Installing firecracker-farm ${version} to ${FC_FARM_INSTALL_DIR}"

  download_and_extract "$version"
  create_symlinks
  run_host_install "$guest_user" "$ssh_key_file"

  ok "firecracker-farm ${version} installed successfully"
  info ""
  info "Next steps:"
  info "  1. Build the Ubuntu template:  sudo bash -c 'source ${FC_FARM_INSTALL_DIR}/lib/image.sh && fc_image_build_template'"
  info "  2. Create a VM:               fc-create myvm --disk-size 20G"
  info "  3. Start it:                   fc-start myvm"
  info "  4. SSH in:                     fc-ssh myvm"
}

main "$@"
