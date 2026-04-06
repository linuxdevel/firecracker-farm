#!/usr/bin/env bash

if [[ -n "${FC_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
readonly FC_COMMON_SH_LOADED=1

fc_repo_root() {
  local script_dir
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  (
    cd -- "$script_dir/.." && pwd
  )
}

fc_version() {
  local root
  root=$(fc_repo_root)
  # Prefer VERSION file (present in release tarballs)
  if [[ -f "$root/VERSION" ]]; then
    cat "$root/VERSION"
    return 0
  fi
  # Fall back to git describe (development checkout)
  if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$root" describe --tags --always 2>/dev/null && return 0
  fi
  printf 'unknown\n'
}

fc_load_config() {
  # shellcheck source=./config.sh
  source "$(fc_repo_root)/lib/config.sh"
}

fc_log() {
  printf '%s\n' "$*"
}

fc_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

fc_running_as_root() {
  [[ "$(id -u)" -eq 0 ]]
}

fc_require_passwordless_sudo() {
  fc_command_exists sudo || {
    fc_error "sudo is required for this command"
    return 1
  }
}

fc_reexec_with_sudo() {
  local script_path=$1
  shift

  fc_require_passwordless_sudo || return 1
  exec sudo -n "$script_path" "$@"
}

fc_info() {
  fc_log "INFO: $*"
}

fc_warn() {
  fc_log "WARN: $*" >&2
}

fc_error() {
  fc_log "ERROR: $*" >&2
}

fc_ok() {
  fc_log "PASS: $*"
}

fc_check_required() {
  local description=$1
  shift

  if "$@"; then
    fc_ok "$description"
    return 0
  fi

  fc_error "Required check failed: $description"
  return 1
}

fc_check_optional() {
  local description=$1
  shift

  if "$@"; then
    fc_ok "$description"
    return 0
  fi

  fc_warn "Optional package missing: $description"
  return 0
}

fc_require_argument_count() {
  local actual=$1
  local expected=$2
  local usage=$3

  if [[ "$actual" -eq "$expected" ]]; then
    return 0
  fi

  fc_error "$usage"
  return 1
}

fc_has_free_space_mib() {
  local path=$1
  local required_mib=$2
  local available_mib

  available_mib=$(df -Pm "$path" 2>/dev/null | awk 'NR == 2 { print $4 }') || return 1
  [[ -n "$available_mib" ]] || return 1
  [[ "$available_mib" =~ ^[0-9]+$ ]] || return 1
  (( available_mib >= required_mib ))
}

fc_size_to_mib() {
  local size=$1
  local number unit

  if [[ ! "$size" =~ ^([0-9]+)([GgMm])$ ]]; then
    fc_error "invalid size '$size'; expected a value like 20G or 512M"
    return 1
  fi

  number=${BASH_REMATCH[1]}
  unit=${BASH_REMATCH[2]}

  case "$unit" in
    G|g)
      printf '%s\n' "$(( number * 1024 ))"
      ;;
    M|m)
      printf '%s\n' "$number"
      ;;
    *)
      fc_error "invalid size unit in '$size'"
      return 1
      ;;
  esac
}

fc_vm_instances_dir() {
  printf '%s/vms\n' "$FC_RUNTIME_ROOT"
}

fc_format_uptime() {
    local total_seconds=$1
    local days hours minutes

    days=$(( total_seconds / 86400 ))
    hours=$(( (total_seconds % 86400) / 3600 ))
    minutes=$(( (total_seconds % 3600) / 60 ))

    if (( days > 0 )); then
        printf '%dd %dh %dm\n' "$days" "$hours" "$minutes"
    elif (( hours > 0 )); then
        printf '%dh %dm\n' "$hours" "$minutes"
    else
        printf '%dm\n' "$minutes"
    fi
}

fc_not_implemented() {
  local command_name=${1:-command}
  fc_log "$command_name is not yet implemented. Repository scaffolding is in progress." >&2
  return 1
}
