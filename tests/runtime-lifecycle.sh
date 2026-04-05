#!/usr/bin/env bash

set -eu

TEST_ENV_ROOT=$(mktemp -d)
export FC_RUNTIME_ROOT="$TEST_ENV_ROOT/runtime"
export FC_LOG_ROOT="$TEST_ENV_ROOT/logs"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_metadata_fixture() {
  local metadata_path=$1
  local runtime_root=$2

  cat > "$metadata_path" <<EOF
VM_NAME=testvm
INSTANCE_DIR=$(dirname -- "$metadata_path")
ROOTFS_FILENAME=rootfs.raw
ROOTFS_PATH=$runtime_root/vms/testvm/rootfs.raw
TAP_NAME=fc-testvm0
MAC_ADDRESS=02:18:8c:c0:a7:f8
BRIDGE_NAME=vmbr0
KERNEL_IMAGE_PATH=$runtime_root/assets/vmlinux.bin
VCPU_COUNT=2
MEM_SIZE_MIB=2048
EOF
}

test_config_rendering_uses_metadata_values() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path output_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  output_path="$tmpdir/config.json"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  : > "$tmpdir/vms/testvm/rootfs.raw"
  : > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_firecracker_render_config "$fixture_metadata_path" "$output_path" || return 1

  grep -q '"kernel_image_path": "vmlinux.bin"' "$output_path" || fail "config missing kernel image filename"
  grep -q '"boot_args": "console=ttyS0 reboot=k panic=1 pci=off quiet loglevel=3"' "$output_path" || fail "config missing conservative quiet boot args"
  grep -q '"path_on_host": "rootfs.raw"' "$output_path" || fail "config missing rootfs filename"
  if grep -q '"drive_id": "seed"' "$output_path"; then
    fail "config still contains removed seed drive entry"
  fi
  grep -q '"vcpu_count": 2' "$output_path" || fail "config missing vcpu count from metadata"
  grep -q '"mem_size_mib": 2048' "$output_path" || fail "config missing memory size from metadata"
  grep -q '"host_dev_name": "fc-testvm0"' "$output_path" || fail "config missing tap name from metadata"
  grep -q '"guest_mac": "02:18:8c:c0:a7:f8"' "$output_path" || fail "config missing MAC address from metadata"
)

test_start_creates_live_tap_and_records_runtime_state() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path api_socket_path jailer_log
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"
  jailer_log="$tmpdir/jailer.log"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_firecracker_pid_from_api_socket() { printf '9876\n'; }
  fc_network_tap_exists() { return 1; }
  fc_network_create_tap() { printf 'create %s %s\n' "$1" "$2" >> "$tmpdir/ip.log"; }
  fc_network_attach_tap_to_bridge() { printf 'attach %s %s\n' "$1" "$2" >> "$tmpdir/ip.log"; }
  fc_network_set_tap_up() { printf 'up %s\n' "$1" >> "$tmpdir/ip.log"; }
  fc_firecracker_launch_jailer() {
    printf '%s\n' "$*" > "$jailer_log"
    : > "$4"
    : > "$5"
    : > "$api_socket_path"
  }
  fc_process_is_running() {
    [[ "$1" == '9876' ]]
  }

  fc_firecracker_start "testvm" || return 1

  [[ -f "$runtime_dir/jailer/firecracker/testvm/root/config.json" ]] || fail "config file missing from jail root"
  [[ -f "$runtime_dir/jailer/firecracker/testvm/root/rootfs.raw" ]] || fail "rootfs not staged into jail root"
  [[ "$(stat -c '%d:%i' "$tmpdir/vms/testvm/rootfs.raw")" == "$(stat -c '%d:%i' "$runtime_dir/jailer/firecracker/testvm/root/rootfs.raw")" ]] || fail "start did not expose the persistent rootfs inode inside the jail root"
  [[ -f "$runtime_dir/jailer/firecracker/testvm/root/vmlinux.bin" ]] || fail "kernel not staged into jail root"
  [[ -f "$pid_path" ]] || fail "pid file missing after start"
  [[ "$(<"$pid_path")" == '9876' ]] || fail "pid file missing expected pid from api socket lookup"
  [[ -f "$state_path" ]] || fail "state file missing after start"
  grep -q '^STATUS=running$' "$state_path" || fail "state file missing running status"
  grep -q '^PID=9876$' "$state_path" || fail "state file missing pid"
  grep -q "^API_SOCKET_PATH=$api_socket_path$" "$state_path" || fail "state file missing api socket path"
  grep -q '^create fc-testvm0 02:18:8c:c0:a7:f8$' "$tmpdir/ip.log" || fail "start did not create the expected tap"
  grep -q '^attach fc-testvm0 vmbr0$' "$tmpdir/ip.log" || fail "start did not attach tap to bridge"
  grep -q '^up fc-testvm0$' "$tmpdir/ip.log" || fail "start did not bring tap up"
  grep -q -- 'config.json api.socket ' "$jailer_log" || fail "jailer launch missing jailed config/socket arguments"
  if grep -q -- '--seccomp-level' "$jailer_log"; then
    fail "jailer launch still uses removed --seccomp-level flag"
  fi
)

test_start_clears_stale_jail_root_before_launch() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir stale_tun_path api_socket_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  stale_tun_path="$runtime_dir/jailer/firecracker/testvm/root/dev/net/tun"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets" "$(dirname -- "$stale_tun_path")"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  printf 'stale device' > "$stale_tun_path"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_firecracker_pid_from_api_socket() { printf '9876\n'; }
  fc_network_tap_exists() { return 0; }
  fc_firecracker_launch_jailer() {
    [[ ! -e "$stale_tun_path" ]] || fail "start reused a stale jail root"
    : > "$4"
    : > "$5"
    : > "$api_socket_path"
  }
  fc_process_is_running() {
    [[ "$1" == '9876' ]]
  }

  fc_firecracker_start "testvm" || return 1

  [[ ! -e "$stale_tun_path" ]] || fail "stale jail-root device node still exists after start"
)

test_start_uses_jailer_pid_file_when_api_socket_owner_lookup_is_empty() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path api_socket_path jailer_pid_file
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"
  jailer_pid_file="$runtime_dir/jailer/firecracker/testvm/root/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_network_tap_exists() { return 0; }
  fc_firecracker_cleanup_start_failure() { fail "start should not fail when the jailer pid file exists"; }
  fc_firecracker_launch_jailer() {
    mkdir -p "$(dirname -- "$jailer_pid_file")"
    printf '9876\n' > "$jailer_pid_file"
    : > "$4"
    : > "$5"
    : > "$api_socket_path"
  }
  fc_firecracker_pid_from_api_socket() {
    return 0
  }
  fc_process_is_running() {
    [[ "$1" == '9876' ]]
  }

  fc_firecracker_start "testvm" || return 1

  [[ -f "$pid_path" ]] || fail "pid file missing after fallback to jailer pid file"
  [[ "$(<"$pid_path")" == '9876' ]] || fail "start did not reuse the jailer pid file"
  [[ -f "$state_path" ]] || fail "state file missing after fallback to jailer pid file"
  grep -q '^PID=9876$' "$state_path" || fail "state file missing pid from jailer pid file"
)

test_start_uses_jailer_pid_file_when_api_socket_lookup_fails() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path api_socket_path jailer_pid_file
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"
  jailer_pid_file="$runtime_dir/jailer/firecracker/testvm/root/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_network_tap_exists() { return 0; }
  fc_firecracker_cleanup_start_failure() { fail "start should fall back to the jailer pid file when api lookup fails"; }
  fc_firecracker_launch_jailer() {
    mkdir -p "$(dirname -- "$jailer_pid_file")"
    printf '9876\n' > "$jailer_pid_file"
    : > "$4"
    : > "$5"
    : > "$api_socket_path"
  }
  fc_firecracker_pid_from_api_socket() {
    return 1
  }
  fc_process_is_running() {
    [[ "$1" == '9876' ]]
  }

  fc_firecracker_start "testvm" || return 1

  [[ -f "$pid_path" ]] || fail "pid file missing after api lookup fallback"
  [[ "$(<"$pid_path")" == '9876' ]] || fail "start did not reuse the jailer pid file after api lookup failure"
  [[ -f "$state_path" ]] || fail "state file missing after api lookup fallback"
  grep -q '^PID=9876$' "$state_path" || fail "state file missing pid after api lookup fallback"
)

test_log_bounding_truncates_existing_logs_before_launch() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path stdout_log_path stderr_log_path log_limit_bytes
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  stdout_log_path="$tmpdir/logs/testvm.stdout.log"
  stderr_log_path="$tmpdir/logs/testvm.stderr.log"
  log_limit_bytes=1024

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets" "$tmpdir/logs"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  perl -e 'print "x" x 4096' > "$stdout_log_path"
  perl -e 'print "y" x 4096' > "$stderr_log_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_firecracker_log_max_bytes() { printf '%s\n' "$log_limit_bytes"; }
  fc_firecracker_pid_from_api_socket() { printf '9876\n'; }
  fc_network_tap_exists() { return 0; }
  fc_firecracker_launch_jailer() {
    : > "$4"
    : > "$5"
    : > "$(fc_firecracker_api_socket_path_from_metadata_path "$fixture_metadata_path")"
  }
  fc_process_is_running() {
    [[ "$1" == '9876' ]]
  }

  fc_firecracker_start "testvm" || return 1

  [[ $(wc -c < "$stdout_log_path") -le $log_limit_bytes ]] || fail "stdout log was not bounded before launch"
  [[ $(wc -c < "$stderr_log_path") -le $log_limit_bytes ]] || fail "stderr log was not bounded before launch"
)

test_runtime_log_capture_bounds_stream_output() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir output_path pipe_path pid_path log_limit_bytes
  tmpdir=$(mktemp -d)
  output_path="$tmpdir/stdout.log"
  pipe_path="$tmpdir/stdout.pipe"
  pid_path="$tmpdir/stdout-log-capture.pid"
  log_limit_bytes=1024

  fc_firecracker_log_max_bytes() { printf '%s\n' "$log_limit_bytes"; }

  fc_firecracker_start_log_capture "$pipe_path" "$output_path" "$pid_path" || return 1
  perl -e 'print "a" x 2048' > "$pipe_path"
  wait "$(<"$pid_path")"

  [[ $(wc -c < "$output_path") -le $log_limit_bytes ]] || fail "runtime log capture exceeded the configured byte limit"
  [[ $(wc -c < "$output_path") -eq $log_limit_bytes ]] || fail "runtime log capture did not retain the configured tail size"
)

test_start_failure_cleans_up_runtime_log_captures_and_pipes() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir stdout_pipe_path stderr_pipe_path
  local stdout_capture_pid_path stderr_capture_pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  stdout_pipe_path="$runtime_dir/stdout.pipe"
  stderr_pipe_path="$runtime_dir/stderr.pipe"
  stdout_capture_pid_path="$runtime_dir/stdout-log-capture.pid"
  stderr_capture_pid_path="$runtime_dir/stderr-log-capture.pid"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_network_tap_exists() { return 0; }
  fc_firecracker_launch_jailer() {
    return 1
  }

  if fc_firecracker_start "testvm"; then
    fail "start unexpectedly succeeded during jailer launch failure"
  fi

  [[ ! -p "$stdout_pipe_path" ]] || fail "stdout pipe still present after failed start"
  [[ ! -p "$stderr_pipe_path" ]] || fail "stderr pipe still present after failed start"
  [[ ! -f "$stdout_capture_pid_path" ]] || fail "stdout capture pid file still present after failed start"
  [[ ! -f "$stderr_capture_pid_path" ]] || fail "stderr capture pid file still present after failed start"
)

test_start_failure_cleans_up_created_tap_and_reconciles_vm_process() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir api_socket_path stdout_pipe_path stderr_pipe_path
  local jailer_pid_file
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"
  stdout_pipe_path="$runtime_dir/stdout.pipe"
  stderr_pipe_path="$runtime_dir/stderr.pipe"
  jailer_pid_file="$runtime_dir/jailer/firecracker/testvm/root/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_log_root() { printf '%s\n' "$tmpdir/logs"; }
  fc_network_tap_exists() {
    [[ -f "$tmpdir/tap-created.log" ]]
  }
  fc_network_create_tap() { printf '%s\n' "$1" > "$tmpdir/tap-created.log"; }
  fc_network_attach_tap_to_bridge() { :; }
  fc_network_set_tap_up() { :; }
  fc_network_delete_tap() { printf '%s\n' "$1" > "$tmpdir/tap-deleted.log"; }
  fc_firecracker_launch_jailer() {
    : > "$4"
    : > "$5"
    mkdir -p "$(dirname -- "$jailer_pid_file")"
    printf '9876\n' > "$jailer_pid_file"
  }
  fc_firecracker_wait_for_api_socket() { : > "$api_socket_path"; }
  fc_firecracker_pid_from_api_socket() { printf '9876\n'; }
  fc_process_is_running() { [[ "$1" == '9876' ]]; }
  fc_signal_process() { printf '%s %s\n' "$1" "$2" > "$tmpdir/reconcile-kill.log"; }
  fc_wait_for_process_exit() { return 0; }
  fc_firecracker_write_state_from_metadata_path() { return 1; }

  if fc_firecracker_start "testvm"; then
    fail "start unexpectedly succeeded during post-launch state write failure"
  fi

  [[ "$(<"$tmpdir/tap-created.log")" == 'fc-testvm0' ]] || fail "start did not create managed tap before failure"
  [[ "$(<"$tmpdir/tap-deleted.log")" == 'fc-testvm0' ]] || fail "failed start did not clean up created tap"
  [[ "$(<"$tmpdir/reconcile-kill.log")" == 'TERM 9876' ]] || fail "failed start did not reconcile launched vm process"
  [[ ! -p "$stdout_pipe_path" ]] || fail "stdout pipe still present after reconciled start failure"
  [[ ! -p "$stderr_pipe_path" ]] || fail "stderr pipe still present after reconciled start failure"
)

test_stop_rejects_unsafe_pid_and_tap_values() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '%s\n' '-1' > "$pid_path"
  cat > "$state_path" <<EOF
VM_NAME=testvm
STATUS=running
PID=-1
API_SOCKET_PATH=$runtime_dir/jailer/firecracker/testvm/root/api.socket
EOF
  printf 'TAP_NAME=vmbr0\n' >> "$fixture_metadata_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() { fail "stop should not probe unsafe pid"; }
  fc_signal_process() { fail "stop should not signal unsafe pid"; }
  fc_network_tap_exists() { return 0; }
  fc_network_delete_tap() { fail "stop should not delete unsafe tap"; }

  if fc_firecracker_stop "testvm"; then
    fail "stop unexpectedly succeeded with unsafe pid/tap metadata"
  fi

  [[ -f "$pid_path" ]] || fail "unsafe stop should not remove pid file"
)

test_start_rejects_unsafe_tap_and_bridge_values() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"

  mkdir -p "$tmpdir/vms/testvm" "$tmpdir/assets"
  printf 'rootfs' > "$tmpdir/vms/testvm/rootfs.raw"
  printf 'kernel' > "$tmpdir/assets/vmlinux.bin"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf 'TAP_NAME=vmbr0\n' >> "$fixture_metadata_path"
  printf 'BRIDGE_NAME=br-bad\n' >> "$fixture_metadata_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_network_create_tap() { fail "start should not create a tap from unsafe metadata"; }
  fc_network_attach_tap_to_bridge() { fail "start should not attach an unsafe bridge"; }

  if fc_firecracker_start "testvm"; then
    fail "start unexpectedly succeeded with unsafe tap/bridge metadata"
  fi
)

test_stop_cleans_up_runtime_log_captures_and_pipes() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path stdout_pipe_path stderr_pipe_path
  local stdout_capture_pid_path stderr_capture_pid_path output_file
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"
  stdout_pipe_path="$runtime_dir/stdout.pipe"
  stderr_pipe_path="$runtime_dir/stderr.pipe"
  stdout_capture_pid_path="$runtime_dir/stdout-log-capture.pid"
  stderr_capture_pid_path="$runtime_dir/stderr-log-capture.pid"
  output_file="$tmpdir/status.out"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '4321\n' > "$pid_path"
  mkfifo "$stdout_pipe_path"
  mkfifo "$stderr_pipe_path"
  cat > "$state_path" <<EOF
VM_NAME=testvm
STATUS=running
PID=4321
API_SOCKET_PATH=$runtime_dir/jailer/firecracker/testvm/root/api.socket
EOF

  bash -c 'exec < "$1"' _ "$stdout_pipe_path" &
  printf '%s\n' "$!" > "$stdout_capture_pid_path"
  bash -c 'exec < "$1"' _ "$stderr_pipe_path" &
  printf '%s\n' "$!" > "$stderr_capture_pid_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() {
    [[ "$1" == '4321' ]]
  }
  fc_signal_process() {
    printf '%s %s\n' "$1" "$2" > "$tmpdir/kill.log"
  }
  fc_wait_for_process_exit() { return 0; }
  fc_network_tap_exists() { return 0; }
  fc_network_delete_tap() { printf '%s\n' "$1" > "$tmpdir/tap-delete.log"; }

  fc_firecracker_status "testvm" > "$output_file" || return 1
  grep -q '^testvm running 4321$' "$output_file" || fail "status output missing running state"

  fc_firecracker_stop "testvm" || return 1

  [[ ! -p "$stdout_pipe_path" ]] || fail "stdout pipe still present after stop"
  [[ ! -p "$stderr_pipe_path" ]] || fail "stderr pipe still present after stop"
  [[ ! -f "$stdout_capture_pid_path" ]] || fail "stdout capture pid file still present after stop"
  [[ ! -f "$stderr_capture_pid_path" ]] || fail "stderr capture pid file still present after stop"
  [[ ! -f "$pid_path" ]] || fail "pid file still present after stop"
  [[ "$(<"$tmpdir/kill.log")" == 'TERM 4321' ]] || fail "stop did not signal the expected pid"
  [[ "$(<"$tmpdir/tap-delete.log")" == 'fc-testvm0' ]] || fail "stop did not delete the live tap"
  grep -q '^STATUS=stopped$' "$state_path" || fail "state file missing stopped status"
)

test_stop_escalates_to_sigkill_on_sigterm_timeout() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path
  local stdout_pipe_path stderr_pipe_path stdout_capture_pid_path stderr_capture_pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '4321\n' > "$pid_path"

  fc_info() { :; }
  fc_warn() { printf '%s\n' "$*" >> "$tmpdir/warn.log"; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() { [[ "$1" == '4321' ]]; }
  fc_signal_process() {
    printf '%s %s\n' "$1" "$2" >> "$tmpdir/kill.log"
  }

  local wait_call_count=0
  fc_wait_for_process_exit() {
    wait_call_count=$((wait_call_count + 1))
    if [[ $wait_call_count -eq 1 ]]; then
      # SIGTERM timeout
      return 1
    fi
    # SIGKILL succeeds
    return 0
  }

  fc_network_tap_exists() { return 1; }
  fc_network_delete_tap() { :; }
  fc_firecracker_cleanup_cgroup() { :; }

  fc_firecracker_stop "testvm" || fail "stop should succeed after SIGKILL escalation"

  grep -q '^TERM 4321$' "$tmpdir/kill.log" || fail "stop did not send SIGTERM first"
  grep -q '^KILL 4321$' "$tmpdir/kill.log" || fail "stop did not escalate to SIGKILL"
  grep -q 'SIGTERM timed out' "$tmpdir/warn.log" || fail "stop did not warn about SIGTERM timeout"
)

test_stop_force_skips_sigterm() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '4321\n' > "$pid_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() { [[ "$1" == '4321' ]]; }
  fc_signal_process() {
    printf '%s %s\n' "$1" "$2" >> "$tmpdir/kill.log"
  }
  fc_wait_for_process_exit() { return 0; }
  fc_network_tap_exists() { return 1; }
  fc_network_delete_tap() { :; }
  fc_firecracker_cleanup_cgroup() { :; }

  fc_firecracker_stop "testvm" 1 || fail "force stop should succeed"

  if grep -q '^TERM ' "$tmpdir/kill.log" 2>/dev/null; then
    fail "force stop should not send SIGTERM"
  fi
  grep -q '^KILL 4321$' "$tmpdir/kill.log" || fail "force stop did not send SIGKILL"
)

test_stop_cleans_up_stale_resources_when_no_pid_file() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  # Deliberately no pid file

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { fail "stale cleanup should not call fc_error: $*"; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_network_tap_exists() { return 0; }
  fc_network_delete_tap() { printf '%s\n' "$1" > "$tmpdir/tap-delete.log"; }
  fc_firecracker_cleanup_cgroup() { printf '%s\n' "$1" > "$tmpdir/cgroup-cleanup.log"; }
  fc_signal_process() { fail "should not signal any process when no pid file exists"; }

  fc_firecracker_stop "testvm" || fail "stop should succeed when no pid file (stale cleanup)"

  [[ -f "$tmpdir/tap-delete.log" ]] || fail "stale cleanup did not delete tap"
  [[ "$(<"$tmpdir/tap-delete.log")" == 'fc-testvm0' ]] || fail "stale cleanup deleted wrong tap"
  [[ -f "$tmpdir/cgroup-cleanup.log" ]] || fail "stale cleanup did not run cgroup cleanup"
  [[ -f "$state_path" ]] || fail "stale cleanup did not write stopped state"
  grep -q '^STATUS=stopped$' "$state_path" || fail "stale cleanup state missing stopped status"
)

test_stop_cleans_up_when_process_already_dead() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '4321\n' > "$pid_path"

  fc_info() { :; }
  fc_warn() { printf '%s\n' "$*" >> "$tmpdir/warn.log"; }
  fc_ok() { :; }
  fc_error() { fail "cleanup of dead process should not call fc_error: $*"; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() { return 1; }
  fc_signal_process() { fail "should not signal a dead process"; }
  fc_wait_for_process_exit() { return 0; }
  fc_network_tap_exists() { return 0; }
  fc_network_delete_tap() { printf '%s\n' "$1" > "$tmpdir/tap-delete.log"; }
  fc_firecracker_cleanup_cgroup() { printf '%s\n' "$1" > "$tmpdir/cgroup-cleanup.log"; }

  fc_firecracker_stop "testvm" || fail "stop should succeed when process is already dead"

  [[ ! -f "$pid_path" ]] || fail "pid file should be removed after dead process cleanup"
  [[ -f "$tmpdir/tap-delete.log" ]] || fail "dead process cleanup did not delete tap"
  [[ -f "$tmpdir/cgroup-cleanup.log" ]] || fail "dead process cleanup did not run cgroup cleanup"
  [[ -f "$state_path" ]] || fail "dead process cleanup did not write stopped state"
  grep -q '^STATUS=stopped$' "$state_path" || fail "dead process cleanup state missing stopped status"
  grep -q 'not running' "$tmpdir/warn.log" || fail "dead process cleanup did not warn about dead process"
)

test_stop_calls_cgroup_cleanup() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir state_path pid_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  state_path="$runtime_dir/state.env"
  pid_path="$runtime_dir/firecracker.pid"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf '4321\n' > "$pid_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_process_is_running() { [[ "$1" == '4321' ]]; }
  fc_signal_process() { :; }
  fc_wait_for_process_exit() { return 0; }
  fc_network_tap_exists() { return 1; }
  fc_network_delete_tap() { :; }
  fc_firecracker_cleanup_cgroup() { printf '%s\n' "$1" > "$tmpdir/cgroup-cleanup.log"; }

  fc_firecracker_stop "testvm" || fail "stop should succeed"

  [[ -f "$tmpdir/cgroup-cleanup.log" ]] || fail "stop did not call cgroup cleanup"
  [[ "$(<"$tmpdir/cgroup-cleanup.log")" == 'testvm' ]] || fail "cgroup cleanup called with wrong vm name"
)

test_vm_info_returns_structured_data_for_running_vm() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path runtime_dir pid_path api_socket_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"
  runtime_dir="$tmpdir/vms/testvm/runtime"
  pid_path="$runtime_dir/firecracker.pid"
  api_socket_path="$runtime_dir/jailer/firecracker/testvm/root/api.socket"

  mkdir -p "$tmpdir/vms/testvm" "$runtime_dir" "$(dirname -- "$api_socket_path")"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  printf 'DISK_SIZE=20G\n' >> "$fixture_metadata_path"
  printf '9876\n' > "$pid_path"
  : > "$api_socket_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }
  fc_firecracker_pid_from_api_socket() { printf '9876\n'; }
  fc_process_is_running() { [[ "$1" == '9876' ]]; }
  fc_network_resolve_guest_ip() { printf '192.168.1.107\n'; }
  ps() { printf '  3661\n'; }

  local info_output
  info_output=$(fc_firecracker_vm_info "testvm") || fail "vm_info failed for running vm"

  local vm_name="" status="" pid="" vcpus="" memory="" disk="" ip="" tap="" bridge="" uptime=""
  local _key _value
  while IFS='=' read -r _key _value; do
    case "$_key" in
      VM_NAME) vm_name=$_value ;;
      STATUS)  status=$_value ;;
      PID)     pid=$_value ;;
      VCPUS)   vcpus=$_value ;;
      MEMORY)  memory=$_value ;;
      DISK)    disk=$_value ;;
      IP)      ip=$_value ;;
      TAP)     tap=$_value ;;
      BRIDGE)  bridge=$_value ;;
      UPTIME)  uptime=$_value ;;
    esac
  done <<< "$info_output"

  [[ "$vm_name" == "testvm" ]] || fail "vm_info VM_NAME='$vm_name' expected 'testvm'"
  [[ "$status" == "running" ]] || fail "vm_info STATUS='$status' expected 'running'"
  [[ "$pid" == "9876" ]] || fail "vm_info PID='$pid' expected '9876'"
  [[ "$vcpus" == "2" ]] || fail "vm_info VCPUS='$vcpus' expected '2'"
  [[ "$memory" == "2048" ]] || fail "vm_info MEMORY='$memory' expected '2048'"
  [[ "$disk" == "20G" ]] || fail "vm_info DISK='$disk' expected '20G'"
  [[ "$ip" == "192.168.1.107" ]] || fail "vm_info IP='$ip' expected '192.168.1.107'"
  [[ "$tap" == "fc-testvm0" ]] || fail "vm_info TAP='$tap' expected 'fc-testvm0'"
  [[ "$bridge" == "vmbr0" ]] || fail "vm_info BRIDGE='$bridge' expected 'vmbr0'"
  [[ "$uptime" == "1h 1m" ]] || fail "vm_info UPTIME='$uptime' expected '1h 1m'"
)

test_vm_info_returns_stopped_defaults_for_stopped_vm() (
  source "$REPO_ROOT/lib/firecracker.sh"

  local tmpdir fixture_metadata_path
  tmpdir=$(mktemp -d)
  fixture_metadata_path="$tmpdir/vms/testvm/vm.env"

  mkdir -p "$tmpdir/vms/testvm"
  write_metadata_fixture "$fixture_metadata_path" "$tmpdir"
  # No pid file, no api socket — VM is stopped

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_firecracker_vm_metadata_path() { printf '%s\n' "$fixture_metadata_path"; }

  local info_output
  info_output=$(fc_firecracker_vm_info "testvm") || fail "vm_info failed for stopped vm"

  local status="" pid="" ip="" uptime=""
  local _key _value
  while IFS='=' read -r _key _value; do
    case "$_key" in
      STATUS) status=$_value ;;
      PID)    pid=$_value ;;
      IP)     ip=$_value ;;
      UPTIME) uptime=$_value ;;
    esac
  done <<< "$info_output"

  [[ "$status" == "stopped" ]] || fail "vm_info STATUS='$status' expected 'stopped'"
  [[ "$pid" == "-" ]] || fail "vm_info PID='$pid' expected '-'"
  [[ "$ip" == "-" ]] || fail "vm_info IP='$ip' expected '-'"
  [[ "$uptime" == "-" ]] || fail "vm_info UPTIME='$uptime' expected '-'"
)

main() {
  test_config_rendering_uses_metadata_values || return 1
  test_start_creates_live_tap_and_records_runtime_state || return 1
  test_start_clears_stale_jail_root_before_launch || return 1
  test_start_uses_jailer_pid_file_when_api_socket_owner_lookup_is_empty || return 1
  test_start_uses_jailer_pid_file_when_api_socket_lookup_fails || return 1
  test_log_bounding_truncates_existing_logs_before_launch || return 1
  test_runtime_log_capture_bounds_stream_output || return 1
  test_start_failure_cleans_up_runtime_log_captures_and_pipes || return 1
  test_start_failure_cleans_up_created_tap_and_reconciles_vm_process || return 1
  test_stop_rejects_unsafe_pid_and_tap_values || return 1
  test_start_rejects_unsafe_tap_and_bridge_values || return 1
  test_stop_cleans_up_runtime_log_captures_and_pipes || return 1
  test_stop_escalates_to_sigkill_on_sigterm_timeout || return 1
  test_stop_force_skips_sigterm || return 1
  test_stop_cleans_up_stale_resources_when_no_pid_file || return 1
  test_stop_cleans_up_when_process_already_dead || return 1
  test_stop_calls_cgroup_cleanup || return 1
  test_vm_info_returns_structured_data_for_running_vm || return 1
  test_vm_info_returns_stopped_defaults_for_stopped_vm || return 1
  printf 'PASS: runtime lifecycle checks\n'
}

main "$@"
