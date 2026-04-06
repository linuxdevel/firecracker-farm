#!/usr/bin/env bash

if [[ -n "${FC_FIRECRACKER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly FC_FIRECRACKER_SH_LOADED=1

# shellcheck source=./common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck source=./network.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/network.sh"
fc_load_config

fc_firecracker_templates_dir() {
  printf '%s/templates\n' "$(fc_repo_root)"
}

fc_firecracker_binary_path() {
  printf '%s/firecracker\n' "$FC_BINARY_ROOT"
}

fc_firecracker_jailer_binary_path() {
  printf '%s/jailer\n' "$FC_BINARY_ROOT"
}

fc_firecracker_log_root() {
  printf '%s\n' "$FC_LOG_ROOT"
}

fc_firecracker_vm_dir() {
  local vm_name=$1
  printf '%s/%s\n' "$(fc_vm_instances_dir)" "$vm_name"
}

fc_firecracker_vm_metadata_path() {
  local vm_name=$1
  printf '%s/vm.env\n' "$(fc_firecracker_vm_dir "$vm_name")"
}

fc_firecracker_vm_dir_from_metadata_path() {
  local metadata_path=$1
  printf '%s\n' "$(dirname -- "$metadata_path")"
}

fc_firecracker_runtime_dir() {
  local vm_name=$1
  printf '%s/runtime\n' "$(fc_firecracker_vm_dir "$vm_name")"
}

fc_firecracker_runtime_dir_from_metadata_path() {
  local metadata_path=$1
  printf '%s/runtime\n' "$(fc_firecracker_vm_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_pid_path() {
  local vm_name=$1
  printf '%s/firecracker.pid\n' "$(fc_firecracker_runtime_dir "$vm_name")"
}

fc_firecracker_pid_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/firecracker.pid\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_state_path() {
  local vm_name=$1
  printf '%s/state.env\n' "$(fc_firecracker_runtime_dir "$vm_name")"
}

fc_firecracker_state_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/state.env\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_jailer_root_dir() {
  local vm_name=$1
  printf '%s/jailer/firecracker/%s/root\n' "$(fc_firecracker_runtime_dir "$vm_name")" "$vm_name"
}

fc_firecracker_jailer_root_dir_from_metadata_path() {
  local metadata_path=$1
  local vm_name

  vm_name=$(fc_firecracker_require_metadata_value "$metadata_path" "VM_NAME") || return 1
  printf '%s/jailer/firecracker/%s/root\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")" "$vm_name"
}

fc_firecracker_jailer_pid_file_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/jailer/firecracker/%s/root/firecracker.pid\n' \
    "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")" \
    "$(fc_firecracker_require_metadata_value "$metadata_path" "VM_NAME")"
}

fc_firecracker_config_path() {
  local vm_name=$1
  printf '%s/config.json\n' "$(fc_firecracker_jailer_root_dir "$vm_name")"
}

fc_firecracker_config_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/config.json\n' "$(fc_firecracker_jailer_root_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_api_socket_path() {
  local vm_name=$1
  printf '%s/api.socket\n' "$(fc_firecracker_jailer_root_dir "$vm_name")"
}

fc_firecracker_api_socket_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/api.socket\n' "$(fc_firecracker_jailer_root_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_stdout_log_path() {
  local vm_name=$1
  printf '%s/%s.stdout.log\n' "$(fc_firecracker_log_root)" "$vm_name"
}

fc_firecracker_stderr_log_path() {
  local vm_name=$1
  printf '%s/%s.stderr.log\n' "$(fc_firecracker_log_root)" "$vm_name"
}

fc_firecracker_log_max_bytes() {
  printf '1048576\n'
}

fc_firecracker_env_get() {
  local metadata_path=$1
  local key=$2

  awk -F= -v key="$key" '$1 == key { sub($1 FS, "", $0); value=$0 } END { if (value != "") print value }' "$metadata_path"
}

fc_firecracker_require_metadata_value() {
  local metadata_path=$1
  local key=$2
  local value

  value=$(fc_firecracker_env_get "$metadata_path" "$key") || return 1
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  fc_error "instance metadata missing required key $key: $metadata_path"
  return 1
}

fc_firecracker_kernel_path() {
  local metadata_path=$1
  local kernel_path

  kernel_path=$(fc_firecracker_env_get "$metadata_path" "KERNEL_IMAGE_PATH") || return 1
  if [[ -n "$kernel_path" ]]; then
    printf '%s\n' "$kernel_path"
    return 0
  fi

  printf '%s/vmlinux.bin\n' "$FC_BINARY_ROOT"
}

fc_firecracker_vcpu_count() {
  local metadata_path=$1
  local value

  value=$(fc_firecracker_env_get "$metadata_path" "VCPU_COUNT") || return 1
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '%s\n' "$FC_DEFAULT_VCPUS"
}

fc_firecracker_mem_size_mib() {
  local metadata_path=$1
  local value

  value=$(fc_firecracker_env_get "$metadata_path" "MEM_SIZE_MIB") || return 1
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  printf '%s\n' "$FC_DEFAULT_MEMORY_MIB"
}

fc_network_tap_exists() {
  local tap_name=$1
  ip link show "$tap_name" >/dev/null 2>&1
}

fc_process_is_running() {
  local pid=$1
  kill -0 "$pid" >/dev/null 2>&1
}

fc_file_exists() {
  local file_path=$1
  [[ -e "$file_path" ]]
}

fc_signal_process() {
  local signal_name=$1
  local pid=$2
  kill -s "$signal_name" "$pid"
}

fc_wait_for_process_exit() {
  local pid=$1
  local attempts=${2:-50}

  while (( attempts > 0 )); do
    if ! fc_process_is_running "$pid"; then
      return 0
    fi
    sleep 0.1
    ((attempts -= 1))
  done

  return 1
}

fc_firecracker_prepare_runtime_dirs() {
  local metadata_path=$1
  local jailer_vm_dir

  jailer_vm_dir="$(dirname -- "$(fc_firecracker_jailer_root_dir_from_metadata_path "$metadata_path")")"

  mkdir -p "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")"
  rm -rf "$jailer_vm_dir"
  mkdir -p "$(fc_firecracker_jailer_root_dir_from_metadata_path "$metadata_path")"
  mkdir -p "$(fc_firecracker_log_root)"
}

fc_firecracker_copy_into_jail_root() {
  local source_path=$1
  local dest_dir=$2

   cp -f -- "$source_path" "$dest_dir/$(basename -- "$source_path")"
}

fc_firecracker_link_into_jail_root() {
  local source_path=$1
  local dest_dir=$2
  local dest_path

  dest_path="$dest_dir/$(basename -- "$source_path")"
  rm -f "$dest_path"
  ln -- "$source_path" "$dest_path"
}

fc_firecracker_bound_log_file() {
  local log_path=$1
  local max_bytes
  local current_size

  max_bytes=$(fc_firecracker_log_max_bytes) || return 1
  mkdir -p "$(dirname -- "$log_path")"
  if [[ ! -f "$log_path" ]]; then
    : > "$log_path"
    return 0
  fi

  current_size=$(wc -c < "$log_path") || return 1
  if (( current_size <= max_bytes )); then
    return 0
  fi

  tail -c "$max_bytes" "$log_path" > "$log_path.tmp" || return 1
  mv -f "$log_path.tmp" "$log_path"
}

fc_firecracker_prepare_logs() {
  local stdout_log_path=$1
  local stderr_log_path=$2

  fc_firecracker_bound_log_file "$stdout_log_path" || return 1
  fc_firecracker_bound_log_file "$stderr_log_path"
}

fc_firecracker_stdout_pipe_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/stdout.pipe\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_stderr_pipe_path_from_metadata_path() {
  local metadata_path=$1
  printf '%s/stderr.pipe\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")"
}

fc_firecracker_log_capture_pid_path_from_metadata_path() {
  local metadata_path=$1
  local stream_name=$2
  printf '%s/%s-log-capture.pid\n' "$(fc_firecracker_runtime_dir_from_metadata_path "$metadata_path")" "$stream_name"
}

fc_firecracker_start_log_capture() {
  local pipe_path=$1
  local output_path=$2
  local pid_path=$3

  rm -f "$pipe_path"
  mkfifo "$pipe_path" || return 1
  fc_firecracker_run_bounded_log_capture "$output_path" < "$pipe_path" &
  printf '%s\n' "$!" > "$pid_path"
}

fc_firecracker_stop_log_capture() {
  local pid_path=$1
  local pipe_path=${2:-}

  if [[ -n "$pipe_path" && -p "$pipe_path" ]]; then
    python3 -c 'import os, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK)
os.close(fd)' "$pipe_path" 2>/dev/null || true
  fi

  if [[ -f "$pid_path" ]]; then
    wait "$(<"$pid_path")" 2>/dev/null || true
    rm -f "$pid_path"
  fi
}

fc_firecracker_cleanup_log_pipes() {
  local metadata_path=$1
  rm -f "$(fc_firecracker_stdout_pipe_path_from_metadata_path "$metadata_path")"
  rm -f "$(fc_firecracker_stderr_pipe_path_from_metadata_path "$metadata_path")"
}

fc_firecracker_cleanup_start_log_capture() {
  local metadata_path=$1
  local stdout_pipe_path stderr_pipe_path stdout_capture_pid_path stderr_capture_pid_path

  stdout_pipe_path=$(fc_firecracker_stdout_pipe_path_from_metadata_path "$metadata_path")
  stderr_pipe_path=$(fc_firecracker_stderr_pipe_path_from_metadata_path "$metadata_path")
  stdout_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stdout)
  stderr_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stderr)

  fc_firecracker_stop_log_capture "$stdout_capture_pid_path" "$stdout_pipe_path"
  fc_firecracker_stop_log_capture "$stderr_capture_pid_path" "$stderr_pipe_path"
  fc_firecracker_cleanup_log_pipes "$metadata_path"
}

fc_firecracker_pid_is_safe() {
  local pid=$1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]]
}

fc_firecracker_require_safe_pid() {
  local pid=$1
  local context=$2

  if fc_firecracker_pid_is_safe "$pid"; then
    printf '%s\n' "$pid"
    return 0
  fi

  fc_error "unsafe pid for $context: $pid"
  return 1
}

fc_firecracker_tap_name_is_managed() {
  local tap_name=$1
  [[ "$tap_name" =~ ^fc-[a-zA-Z0-9-]+0$ ]]
}

fc_firecracker_require_managed_tap_name() {
  local tap_name=$1
  local context=$2

  if fc_firecracker_tap_name_is_managed "$tap_name"; then
    printf '%s\n' "$tap_name"
    return 0
  fi

  fc_error "unsafe tap name for $context: $tap_name"
  return 1
}

fc_firecracker_bridge_name_is_managed() {
  local bridge_name=$1
  [[ "$bridge_name" == "$FC_DEFAULT_BRIDGE" ]]
}

fc_firecracker_require_managed_bridge_name() {
  local bridge_name=$1
  local context=$2

  if fc_firecracker_bridge_name_is_managed "$bridge_name"; then
    printf '%s\n' "$bridge_name"
    return 0
  fi

  fc_error "unsafe bridge name for $context: $bridge_name"
  return 1
}

fc_firecracker_cleanup_start_failure() {
  local metadata_path=$1
  local tap_name=${2:-}
  local launched_pid=${3:-}
  local pid_path state_path

  pid_path=$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")
  state_path=$(fc_firecracker_state_path_from_metadata_path "$metadata_path")

  if [[ -n "$launched_pid" ]] && fc_firecracker_pid_is_safe "$launched_pid"; then
    if fc_process_is_running "$launched_pid"; then
      fc_signal_process TERM "$launched_pid" || true
      fc_wait_for_process_exit "$launched_pid" || true
    fi
  fi

  if [[ -n "$tap_name" ]] && fc_firecracker_tap_name_is_managed "$tap_name"; then
    if fc_network_tap_exists "$tap_name"; then
      fc_network_delete_tap "$tap_name" || true
    fi
  fi

  fc_firecracker_cleanup_start_log_capture "$metadata_path"
  rm -f "$pid_path" "$state_path"
}

fc_firecracker_run_bounded_log_capture() {
  local output_path=$1
  local max_bytes

  max_bytes=$(fc_firecracker_log_max_bytes) || return 1
  python3 -c 'import os, sys
output_path = sys.argv[1]
max_bytes = int(sys.argv[2])
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "ab+") as handle:
    while True:
        data = sys.stdin.buffer.read(65536)
        if not data:
            break
        handle.seek(0, os.SEEK_END)
        handle.write(data)
        end_pos = handle.tell()
        if end_pos <= max_bytes:
            handle.flush()
            continue
        handle.seek(end_pos - max_bytes)
        tail = handle.read(max_bytes)
        handle.seek(0)
        handle.write(tail)
        handle.seek(max_bytes)
        handle.truncate()
        handle.flush()' "$output_path" "$max_bytes"
}

fc_firecracker_stage_assets() {
  local metadata_path=$1
  local root_dir rootfs_path kernel_path jailed_rootfs_path

  root_dir=$(fc_firecracker_jailer_root_dir_from_metadata_path "$metadata_path") || return 1
  rootfs_path=$(fc_firecracker_require_metadata_value "$metadata_path" "ROOTFS_PATH") || return 1
  kernel_path=$(fc_firecracker_kernel_path "$metadata_path") || return 1

  [[ -f "$rootfs_path" ]] || {
    fc_error "rootfs image not found: $rootfs_path"
    return 1
  }
  [[ -f "$kernel_path" ]] || {
    fc_error "kernel image not found: $kernel_path"
    return 1
  }

  fc_firecracker_link_into_jail_root "$rootfs_path" "$root_dir" || return 1
  fc_firecracker_copy_into_jail_root "$kernel_path" "$root_dir" || return 1

  # The jailer user needs read-write access to the rootfs disk image.
  # The kernel only needs to be readable (it's loaded once at boot).
  # When FC_JAILER_UID is 0 (root/default), the rootfs is already accessible.
  if (( FC_JAILER_UID != 0 )); then
    jailed_rootfs_path="$root_dir/$(basename -- "$rootfs_path")"
    chown "${FC_JAILER_UID}:${FC_JAILER_GID}" "$jailed_rootfs_path" || return 1
  fi
}

fc_firecracker_write_state() {
  local vm_name=$1
  local status=$2
  local pid=$3
  local api_socket_path=$4

  cat > "$(fc_firecracker_state_path "$vm_name")" <<EOF
VM_NAME=$vm_name
STATUS=$status
PID=$pid
API_SOCKET_PATH=$api_socket_path
EOF
}

fc_firecracker_write_state_from_metadata_path() {
  local metadata_path=$1
  local vm_name=$2
  local status=$3
  local pid=$4
  local api_socket_path=$5

  cat > "$(fc_firecracker_state_path_from_metadata_path "$metadata_path")" <<EOF
VM_NAME=$vm_name
STATUS=$status
PID=$pid
API_SOCKET_PATH=$api_socket_path
EOF
}

fc_firecracker_render_config() {
  local metadata_path=$1
  local output_path=$2
  local template_path rendered
  local kernel_filename rootfs_filename tap_name mac_address vcpu_count mem_size_mib

  template_path="$(fc_firecracker_templates_dir)/vm-config.json.tmpl"
  rendered=$(<"$template_path") || return 1
  kernel_filename=$(basename -- "$(fc_firecracker_kernel_path "$metadata_path")") || return 1
  rootfs_filename=$(basename -- "$(fc_firecracker_require_metadata_value "$metadata_path" "ROOTFS_PATH")") || return 1
  tap_name=$(fc_firecracker_require_metadata_value "$metadata_path" "TAP_NAME") || return 1
  mac_address=$(fc_firecracker_require_metadata_value "$metadata_path" "MAC_ADDRESS") || return 1
  vcpu_count=$(fc_firecracker_vcpu_count "$metadata_path") || return 1
  mem_size_mib=$(fc_firecracker_mem_size_mib "$metadata_path") || return 1

  rendered=${rendered//"{{KERNEL_IMAGE_PATH}}"/$kernel_filename}
  rendered=${rendered//"{{ROOTFS_PATH}}"/$rootfs_filename}
  rendered=${rendered//"{{TAP_NAME}}"/$tap_name}
  rendered=${rendered//"{{MAC_ADDRESS}}"/$mac_address}
  rendered=${rendered//"{{VCPU_COUNT}}"/$vcpu_count}
  rendered=${rendered//"{{MEM_SIZE_MIB}}"/$mem_size_mib}
  printf '%s\n' "$rendered" > "$output_path"
}

fc_firecracker_pid_from_api_socket() {
  local api_socket_path=$1

  fuser "$api_socket_path" 2>/dev/null | awk 'NF { print $1; exit }'
}

fc_firecracker_pid_from_jailer_pid_file() {
  local metadata_path=$1
  local pid_file

  pid_file=$(fc_firecracker_jailer_pid_file_path_from_metadata_path "$metadata_path") || return 1
  [[ -f "$pid_file" ]] || return 1
  <"$pid_file" tr -d '[:space:]'
}

fc_firecracker_launch_jailer() {
  local vm_name=$1
  local config_path=$2
  local api_socket_name=$3
  local stdout_log_path=$4
  local stderr_log_path=$5
  local foreground=${6:-0}

  local jailer_args=(
    --id "$vm_name"
    --exec-file "$(fc_firecracker_binary_path)"
    --uid "$FC_JAILER_UID"
    --gid "$FC_JAILER_GID"
    --chroot-base-dir "$(fc_firecracker_runtime_dir "$vm_name")/jailer"
  )

  if (( ! foreground )); then
    jailer_args+=( --daemonize )
  fi

  jailer_args+=( -- --config-file "$config_path" --api-sock "$api_socket_name" )

  if (( foreground )); then
    # exec replaces this process — used by systemd Type=simple
    exec "$(fc_firecracker_jailer_binary_path)" "${jailer_args[@]}" \
      >>"$stdout_log_path" 2>>"$stderr_log_path"
  else
    "$(fc_firecracker_jailer_binary_path)" "${jailer_args[@]}" \
      >>"$stdout_log_path" 2>>"$stderr_log_path"
  fi
}

fc_firecracker_wait_for_api_socket() {
  local api_socket_path=$1
  local attempts=${2:-50}

  while (( attempts > 0 )); do
    if fc_file_exists "$api_socket_path"; then
      return 0
    fi
    sleep 0.1
    ((attempts -= 1))
  done

  fc_error "timed out waiting for Firecracker API socket: $api_socket_path"
  return 1
}

fc_firecracker_setup_and_launch() {
  # Shared setup for both daemonized and exec modes.
  # Sets up networking, stages assets, renders config.
  # Returns the metadata_path, config_path, api_socket_path, and tap state
  # via variables in the caller's scope (nameref).
  local vm_name=$1
  local -n _metadata_path_ref=$2
  local -n _config_path_ref=$3
  local -n _api_socket_path_ref=$4
  local -n _tap_created_ref=$5
  local -n _stdout_log_path_ref=$6
  local -n _stderr_log_path_ref=$7

  local tap_name mac_address bridge_name

  _metadata_path_ref=$(fc_firecracker_vm_metadata_path "$vm_name")
  [[ -f "$_metadata_path_ref" ]] || {
    fc_error "instance metadata not found: $_metadata_path_ref"
    return 1
  }

  _config_path_ref=$(fc_firecracker_config_path_from_metadata_path "$_metadata_path_ref")
  _api_socket_path_ref=$(fc_firecracker_api_socket_path_from_metadata_path "$_metadata_path_ref")
  _stdout_log_path_ref=$(fc_firecracker_stdout_log_path "$vm_name")
  _stderr_log_path_ref=$(fc_firecracker_stderr_log_path "$vm_name")
  _tap_created_ref=0

  tap_name=$(fc_firecracker_require_metadata_value "$_metadata_path_ref" "TAP_NAME") || return 1
  tap_name=$(fc_firecracker_require_managed_tap_name "$tap_name" "start") || return 1
  mac_address=$(fc_firecracker_require_metadata_value "$_metadata_path_ref" "MAC_ADDRESS") || return 1
  bridge_name=$(fc_firecracker_require_metadata_value "$_metadata_path_ref" "BRIDGE_NAME") || return 1
  bridge_name=$(fc_firecracker_require_managed_bridge_name "$bridge_name" "start") || return 1

  if [[ -f "$(fc_firecracker_pid_path_from_metadata_path "$_metadata_path_ref")" ]]; then
    fc_error "VM already has a recorded pid: $vm_name"
    return 1
  fi

  fc_firecracker_prepare_runtime_dirs "$_metadata_path_ref" || return 1
  fc_firecracker_prepare_logs "$_stdout_log_path_ref" "$_stderr_log_path_ref" || return 1
  rm -f "$_api_socket_path_ref"

  if ! fc_network_tap_exists "$tap_name"; then
    fc_network_create_tap "$tap_name" "$mac_address" || {
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref"
      return 1
    }
    _tap_created_ref=1
    if ! fc_network_attach_tap_to_bridge "$tap_name" "$bridge_name"; then
      fc_network_delete_tap "$tap_name" || true
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref"
      return 1
    fi
    if ! fc_network_set_tap_up "$tap_name"; then
      fc_network_delete_tap "$tap_name" || true
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref"
      return 1
    fi
  fi

  if ! fc_firecracker_stage_assets "$_metadata_path_ref"; then
    if (( _tap_created_ref )); then
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref" "$tap_name"
    else
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref"
    fi
    return 1
  fi
  if ! fc_firecracker_render_config "$_metadata_path_ref" "$_config_path_ref"; then
    if (( _tap_created_ref )); then
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref" "$tap_name"
    else
      fc_firecracker_cleanup_start_failure "$_metadata_path_ref"
    fi
    return 1
  fi
}

fc_firecracker_start_exec() {
  # Start a VM by exec'ing into the jailer (foreground, no daemonize).
  # Used by systemd Type=simple — this function never returns on success.
  local vm_name=$1
  local metadata_path config_path api_socket_path stdout_log_path stderr_log_path
  local tap_created

  fc_firecracker_setup_and_launch "$vm_name" \
    metadata_path config_path api_socket_path tap_created \
    stdout_log_path stderr_log_path || return 1

  # Write PID file with current PID — exec preserves PID
  printf '%s\n' "$$" > "$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")"
  fc_firecracker_write_state_from_metadata_path "$metadata_path" "$vm_name" running "$$" "$api_socket_path"

  # exec replaces this process with jailer→firecracker (foreground)
  # systemd captures stdout/stderr via journal
  fc_firecracker_launch_jailer \
    "$vm_name" \
    "$(basename -- "$config_path")" \
    "$(basename -- "$api_socket_path")" \
    "$stdout_log_path" \
    "$stderr_log_path" \
    1  # foreground=1 → exec, no --daemonize

  # If we reach here, exec failed
  fc_error "exec into jailer failed for $vm_name"
  return 1
}

fc_firecracker_start() {
  # Start a VM with daemonization (interactive / non-systemd mode).
  # Launches jailer with --daemonize, discovers PID, writes state.
  local vm_name=$1
  local metadata_path config_path api_socket_path stdout_log_path stderr_log_path
  local stdout_pipe_path stderr_pipe_path stdout_capture_pid_path stderr_capture_pid_path
  local tap_created pid launched_pid=

  fc_firecracker_setup_and_launch "$vm_name" \
    metadata_path config_path api_socket_path tap_created \
    stdout_log_path stderr_log_path || return 1

  stdout_pipe_path=$(fc_firecracker_stdout_pipe_path_from_metadata_path "$metadata_path")
  stderr_pipe_path=$(fc_firecracker_stderr_pipe_path_from_metadata_path "$metadata_path")
  stdout_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stdout)
  stderr_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stderr)

  fc_firecracker_start_log_capture "$stdout_pipe_path" "$stdout_log_path" "$stdout_capture_pid_path" || return 1
  fc_firecracker_start_log_capture "$stderr_pipe_path" "$stderr_log_path" "$stderr_capture_pid_path" || {
    fc_firecracker_cleanup_start_log_capture "$metadata_path"
    return 1
  }

  fc_firecracker_launch_jailer \
    "$vm_name" \
    "$(basename -- "$config_path")" \
    "$(basename -- "$api_socket_path")" \
    "$stdout_pipe_path" \
    "$stderr_pipe_path" \
    0 || {
      if (( tap_created )); then
        fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)"
      else
        fc_firecracker_cleanup_start_failure "$metadata_path"
      fi
      return 1
    }

  launched_pid=$(fc_firecracker_pid_from_jailer_pid_file "$metadata_path" 2>/dev/null || true)
  if [[ -z "$launched_pid" ]]; then
    launched_pid=$(fc_firecracker_pid_from_api_socket "$api_socket_path" 2>/dev/null || true)
  fi
  if [[ -n "$launched_pid" ]]; then
    launched_pid=$(fc_firecracker_require_safe_pid "$launched_pid" "start reconciliation") || launched_pid=
  fi

  fc_firecracker_wait_for_api_socket "$api_socket_path" || {
    if (( tap_created )); then
      fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)" "$launched_pid"
    else
      fc_firecracker_cleanup_start_failure "$metadata_path" "" "$launched_pid"
    fi
    return 1
  }
  pid=$(fc_firecracker_pid_from_api_socket "$api_socket_path" 2>/dev/null || true)
  if [[ -z "$pid" && -n "$launched_pid" ]]; then
    pid=$launched_pid
  fi
  pid=$(fc_firecracker_require_safe_pid "$pid" "start") || {
    if (( tap_created )); then
      fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)" "$launched_pid"
    else
      fc_firecracker_cleanup_start_failure "$metadata_path" "" "$launched_pid"
    fi
    return 1
  }
  if [[ -z "$pid" ]]; then
    fc_error "unable to determine Firecracker pid from API socket: $api_socket_path"
    if (( tap_created )); then
      fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)" "$launched_pid"
    else
      fc_firecracker_cleanup_start_failure "$metadata_path" "" "$launched_pid"
    fi
    return 1
  fi

  if ! printf '%s\n' "$pid" > "$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")"; then
    if (( tap_created )); then
      fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)" "$pid"
    else
      fc_firecracker_cleanup_start_failure "$metadata_path" "" "$pid"
    fi
    return 1
  fi
  if ! fc_firecracker_write_state_from_metadata_path "$metadata_path" "$vm_name" running "$pid" "$api_socket_path"; then
    if (( tap_created )); then
      fc_firecracker_cleanup_start_failure "$metadata_path" "$(fc_firecracker_require_metadata_value "$metadata_path" TAP_NAME)" "$pid"
    else
      fc_firecracker_cleanup_start_failure "$metadata_path" "" "$pid"
    fi
    return 1
  fi
  fc_ok "Started VM $vm_name"
}

fc_firecracker_cleanup_cgroup() {
  local vm_name=$1
  local cgroup_dir="/sys/fs/cgroup/firecracker/${vm_name}"

  [[ -d "$cgroup_dir" ]] || return 0

  # Kill any remaining processes in the cgroup
  local procs_file="$cgroup_dir/cgroup.procs"
  if [[ -f "$procs_file" ]]; then
    local remaining_pid
    while IFS= read -r remaining_pid; do
      [[ -n "$remaining_pid" ]] || continue
      fc_firecracker_pid_is_safe "$remaining_pid" || continue
      fc_warn "killing orphaned process $remaining_pid in cgroup for $vm_name"
      kill -KILL "$remaining_pid" 2>/dev/null || true
    done < "$procs_file"
    # Give kernel a moment to reap
    sleep 0.2
  fi

  # Try to remove the cgroup directory (only succeeds when empty)
  rmdir "$cgroup_dir" 2>/dev/null || true
}

fc_firecracker_stop() {
  local vm_name=$1
  local force=${2:-0}
  local metadata_path pid_path state_path tap_name pid api_socket_path
  local stdout_pipe_path stderr_pipe_path stdout_capture_pid_path stderr_capture_pid_path

  metadata_path=$(fc_firecracker_vm_metadata_path "$vm_name")
  pid_path=$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")
  state_path=$(fc_firecracker_state_path_from_metadata_path "$metadata_path")
  stdout_pipe_path=$(fc_firecracker_stdout_pipe_path_from_metadata_path "$metadata_path")
  stderr_pipe_path=$(fc_firecracker_stderr_pipe_path_from_metadata_path "$metadata_path")
  stdout_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stdout)
  stderr_capture_pid_path=$(fc_firecracker_log_capture_pid_path_from_metadata_path "$metadata_path" stderr)

  [[ -f "$metadata_path" ]] || {
    fc_error "instance metadata not found: $metadata_path"
    return 1
  }
  if [[ ! -f "$pid_path" ]]; then
    # VM may already be stopped — clean up any stale resources
    fc_warn "No PID file for VM $vm_name, cleaning up stale resources"
    tap_name=$(fc_firecracker_require_metadata_value "$metadata_path" "TAP_NAME") || return 1
    tap_name=$(fc_firecracker_require_managed_tap_name "$tap_name" "stop") || return 1
    if fc_network_tap_exists "$tap_name"; then
      fc_network_delete_tap "$tap_name" || true
    fi
    fc_firecracker_cleanup_cgroup "$vm_name"
    fc_firecracker_cleanup_start_log_capture "$metadata_path"
    fc_firecracker_write_state_from_metadata_path "$metadata_path" "$vm_name" stopped - "$(fc_firecracker_api_socket_path_from_metadata_path "$metadata_path")" || true
    fc_ok "Cleaned up stale resources for VM $vm_name"
    return 0
  fi

  pid=$(<"$pid_path")
  pid=$(fc_firecracker_require_safe_pid "$pid" "stop") || return 1
  api_socket_path=$(fc_firecracker_api_socket_path_from_metadata_path "$metadata_path")
  if fc_file_exists "$api_socket_path"; then
    local socket_pid
    socket_pid=$(fc_firecracker_pid_from_api_socket "$api_socket_path" 2>/dev/null || true)
    if [[ -n "$socket_pid" ]] && fc_firecracker_pid_is_safe "$socket_pid"; then
      pid=$socket_pid
    fi
  fi

  if fc_process_is_running "$pid"; then
    if (( force )); then
      fc_warn "Force-stopping VM $vm_name, sending SIGKILL"
      fc_signal_process KILL "$pid" || return 1
    else
      fc_signal_process TERM "$pid" || return 1
      if ! fc_wait_for_process_exit "$pid"; then
        fc_warn "SIGTERM timed out for VM $vm_name, escalating to SIGKILL"
        fc_signal_process KILL "$pid" || return 1
      fi
    fi
    if ! fc_wait_for_process_exit "$pid" 20; then
      fc_error "VM process $pid did not exit after SIGKILL: $vm_name"
      return 1
    fi
  else
    fc_warn "VM process $pid is not running for $vm_name, cleaning up stale state"
  fi

  tap_name=$(fc_firecracker_require_metadata_value "$metadata_path" "TAP_NAME") || return 1
  tap_name=$(fc_firecracker_require_managed_tap_name "$tap_name" "stop") || return 1
  if fc_network_tap_exists "$tap_name"; then
    fc_network_delete_tap "$tap_name" || return 1
  fi

  fc_firecracker_cleanup_cgroup "$vm_name"

  fc_firecracker_stop_log_capture "$stdout_capture_pid_path" "$stdout_pipe_path"
  fc_firecracker_stop_log_capture "$stderr_capture_pid_path" "$stderr_pipe_path"
  fc_firecracker_cleanup_log_pipes "$metadata_path"
  rm -f "$pid_path"
  fc_firecracker_write_state_from_metadata_path "$metadata_path" "$vm_name" stopped - "$(fc_firecracker_api_socket_path_from_metadata_path "$metadata_path")" || return 1
  [[ -f "$state_path" ]] || return 1
  fc_ok "Stopped VM $vm_name"
}

fc_firecracker_vm_info() {
    local vm_name=$1
    local metadata_path pid_path pid status=stopped api_socket_path
    local vcpu_count mem_size_mib disk_size tap_name bridge_name mac_address ip_addr uptime_str

    metadata_path=$(fc_firecracker_vm_metadata_path "$vm_name")
    [[ -f "$metadata_path" ]] || {
        fc_error "instance metadata not found: $metadata_path"
        return 1
    }

    # Read static config from vm.env
    vcpu_count=$(fc_firecracker_vcpu_count "$metadata_path")
    mem_size_mib=$(fc_firecracker_mem_size_mib "$metadata_path")
    disk_size=$(fc_firecracker_env_get "$metadata_path" "DISK_SIZE")
    tap_name=$(fc_firecracker_env_get "$metadata_path" "TAP_NAME")
    bridge_name=$(fc_firecracker_env_get "$metadata_path" "BRIDGE_NAME")
    mac_address=$(fc_firecracker_env_get "$metadata_path" "MAC_ADDRESS")

    # Determine runtime status
    pid_path=$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")
    api_socket_path=$(fc_firecracker_api_socket_path_from_metadata_path "$metadata_path")
    pid="-"
    ip_addr="-"
    uptime_str="-"

    if fc_file_exists "$api_socket_path"; then
        local socket_pid
        socket_pid=$(fc_firecracker_pid_from_api_socket "$api_socket_path" 2>/dev/null || true)
        if [[ -n "$socket_pid" ]] && fc_firecracker_pid_is_safe "$socket_pid" && fc_process_is_running "$socket_pid"; then
            status=running
            pid=$socket_pid
            printf '%s\n' "$pid" > "$pid_path"
        fi
    fi

    if [[ "$status" != "running" && -f "$pid_path" ]]; then
        local file_pid
        file_pid=$(<"$pid_path")
        if fc_firecracker_pid_is_safe "$file_pid" && fc_process_is_running "$file_pid"; then
            status=running
            pid=$file_pid
        fi
    fi

    # Resolve IP and uptime for running VMs
    if [[ "$status" == "running" && -n "$mac_address" ]]; then
        ip_addr=$(fc_network_resolve_guest_ip "$mac_address" "${bridge_name:-$FC_DEFAULT_BRIDGE}" 2>/dev/null) || ip_addr="-"
    fi

    if [[ "$status" == "running" && "$pid" != "-" ]]; then
        local elapsed_seconds
        elapsed_seconds=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ') || elapsed_seconds=""
        if [[ -n "$elapsed_seconds" ]]; then
            uptime_str=$(fc_format_uptime "$elapsed_seconds")
        fi
    fi

    # Output as key=value pairs
    printf 'VM_NAME=%s\n' "$vm_name"
    printf 'STATUS=%s\n' "$status"
    printf 'PID=%s\n' "$pid"
    printf 'VCPUS=%s\n' "${vcpu_count:-${FC_DEFAULT_VCPUS}}"
    printf 'MEMORY=%s\n' "${mem_size_mib:-${FC_DEFAULT_MEMORY_MIB}}"
    printf 'DISK=%s\n' "${disk_size:--}"
    printf 'IP=%s\n' "$ip_addr"
    printf 'TAP=%s\n' "${tap_name:--}"
    printf 'BRIDGE=%s\n' "${bridge_name:--}"
    printf 'UPTIME=%s\n' "$uptime_str"
}

fc_firecracker_status() {
  local vm_name=$1
  local metadata_path pid_path pid status=stopped api_socket_path

  metadata_path=$(fc_firecracker_vm_metadata_path "$vm_name")
  [[ -f "$metadata_path" ]] || {
    fc_error "instance metadata not found: $metadata_path"
    return 1
  }

  pid_path=$(fc_firecracker_pid_path_from_metadata_path "$metadata_path")
  api_socket_path=$(fc_firecracker_api_socket_path_from_metadata_path "$metadata_path")
  if fc_file_exists "$api_socket_path"; then
    pid=$(fc_firecracker_pid_from_api_socket "$api_socket_path") || return 1
    if [[ -n "$pid" ]] && fc_firecracker_pid_is_safe "$pid" && fc_process_is_running "$pid"; then
      printf '%s\n' "$pid" > "$pid_path"
      printf '%s %s %s\n' "$vm_name" running "$pid"
      return 0
    fi
  fi

  if [[ -f "$pid_path" ]]; then
    pid=$(<"$pid_path")
    if fc_firecracker_pid_is_safe "$pid" && fc_process_is_running "$pid"; then
      status=running
      printf '%s %s %s\n' "$vm_name" "$status" "$pid"
      return 0
    fi
  fi

  printf '%s %s -\n' "$vm_name" "$status"
}
