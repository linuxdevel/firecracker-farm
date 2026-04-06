#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_disk_size_parser_accepts_gib_and_mib() (
  source "$REPO_ROOT/lib/common.sh"

  [[ "$(fc_size_to_mib 20G)" == "20480" ]] || fail "20G did not parse to 20480 MiB"
  [[ "$(fc_size_to_mib 512M)" == "512" ]] || fail "512M did not parse to 512 MiB"

  if fc_size_to_mib 20 >/dev/null 2>&1; then
    fail "size without unit unexpectedly parsed"
  fi
)

test_instance_creation_requires_existing_template() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir
  tmpdir=$(mktemp -d)

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_raw_path() { printf '%s\n' "$tmpdir/images/ubuntu-template.raw"; }
  fc_has_free_space_mib() { return 0; }

  if fc_image_create_instance_disk "testvm" "20G" "testuser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test"; then
    fail "instance creation unexpectedly succeeded without template image"
  fi

  [[ ! -d "$tmpdir/vms/testvm" ]] || fail "instance directory created despite missing template"
)

test_instance_creation_clones_resizes_and_writes_metadata() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir metadata_path disk_path
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/images"
  printf 'template-image' > "$tmpdir/images/ubuntu-template.raw"
  metadata_path="$tmpdir/vms/testvm/vm.env"
  disk_path="$tmpdir/vms/testvm/rootfs.raw"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_raw_path() { printf '%s\n' "$tmpdir/images/ubuntu-template.raw"; }
  fc_image_user_data_path() { printf '%s\n' "$tmpdir/images/ubuntu-template-user-data.yaml"; }
  fc_has_free_space_mib() { return 0; }
  qemu-img() {
    if [[ "$1" == "resize" ]]; then
      printf '%s\n' "$*" > "$tmpdir/qemu-img.log"
      return 0
    fi

    return 1
  }
  resize2fs() {
    printf '%s\n' "$*" > "$tmpdir/resize2fs.log"
    return 0
  }
  # Mock seed injection (requires root for loop mount in production)
  fc_image_create_instance_seed() {
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" > "$tmpdir/seed-inject.log"
    return 0
  }

  fc_image_create_instance_disk "testvm" "20G" "testuser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" || return 1

  [[ -f "$disk_path" ]] || fail "instance disk file was not created"
  [[ "$(<"$disk_path")" == "template-image" ]] || fail "instance disk was not cloned from template"
  [[ -f "$metadata_path" ]] || fail "instance metadata file was not created"
  grep -q '^VM_NAME=testvm$' "$metadata_path" || fail "metadata missing VM_NAME"
  grep -q '^DISK_SIZE=20G$' "$metadata_path" || fail "metadata missing DISK_SIZE"
  grep -q "^ROOTFS_PATH=${disk_path}$" "$metadata_path" || fail "metadata missing ROOTFS_PATH"
  grep -q '^ROOTFS_FILENAME=rootfs.raw$' "$metadata_path" || fail "metadata missing ROOTFS_FILENAME"
  grep -q "^TEMPLATE_PATH=${tmpdir}/images/ubuntu-template.raw$" "$metadata_path" || fail "metadata missing TEMPLATE_PATH"
  [[ "$(<"$tmpdir/qemu-img.log")" == "resize $disk_path 20G" ]] || fail "qemu-img resize was not called with the requested size"
  [[ -f "$tmpdir/resize2fs.log" ]] || fail "resize2fs was not called to expand the filesystem"
  [[ "$(<"$tmpdir/resize2fs.log")" == "-f $disk_path" ]] || fail "resize2fs was not called with the correct arguments"
  [[ -f "$tmpdir/seed-inject.log" ]] || fail "seed injection was not called"
  [[ "$(<"$tmpdir/seed-inject.log")" == "testvm $disk_path testuser ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" ]] || fail "seed injection was not called with correct arguments"
)

test_fc_create_requires_credentials_in_non_interactive_mode() (
  local tmpdir output_file status

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"

  # Stub id to return root so fc-create skips sudo re-exec and reaches
  # the credential validation logic.
  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then printf '0\n'; else /usr/bin/id "$@"; fi
EOF
  chmod +x "$tmpdir/bin/id"

  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    bash "$REPO_ROOT/bin/fc-create" testvm < /dev/null >"$output_file" 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "fc-create unexpectedly succeeded without credentials in non-interactive mode"
  grep -q 'is required when stdin is not interactive' "$output_file" || fail "fc-create did not report the required non-interactive error"
)

test_fc_create_records_network_identity_metadata_without_live_ip_changes() (
  local tmpdir metadata_path

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/images"
  printf 'template-image' > "$tmpdir/images/ubuntu-template.raw"
  metadata_path="$tmpdir/vms/testvm/vm.env"

  source "$REPO_ROOT/lib/image.sh"
  source "$REPO_ROOT/lib/network.sh"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_raw_path() { printf '%s\n' "$tmpdir/images/ubuntu-template.raw"; }
  fc_image_user_data_path() { printf '%s\n' "$tmpdir/images/ubuntu-template-user-data.yaml"; }
  fc_has_free_space_mib() { return 0; }
  qemu-img() {
    if [[ "$1" == "resize" ]]; then
      return 0
    fi

    return 1
  }
  resize2fs() {
    return 0
  }
  # Mock seed injection (requires root for loop mount in production)
  fc_image_create_instance_seed() { return 0; }
  ip() {
    printf '%s\n' "$*" >> "$tmpdir/ip.log"
  }

  printf '%s\n' '#cloud-config' > "$tmpdir/images/ubuntu-template-user-data.yaml"

  fc_image_create_instance_disk "testvm" "20G" "testuser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" || return 1
  fc_network_prepare_instance_metadata "testvm" "$metadata_path" || return 1
  grep -q '^TAP_NAME=fc-testvm0$' "$metadata_path" || fail "metadata missing TAP_NAME"
  grep -q '^MAC_ADDRESS=02:18:8c:c0:a7:f8$' "$metadata_path" || fail "metadata missing stable MAC_ADDRESS"
  grep -q '^BRIDGE_NAME=vmbr0$' "$metadata_path" || fail "metadata missing BRIDGE_NAME"
  [[ ! -e "$tmpdir/ip.log" ]] || fail "fc-create unexpectedly mutated live host networking"
)

test_fc_create_reexecs_with_sudo_for_operator_flow() (
  local tmpdir sudo_log metadata_path

  tmpdir=$(mktemp -d)
  sudo_log="$tmpdir/sudo.log"
  metadata_path="$tmpdir/runtime/vms/testvm/vm.env"
  mkdir -p "$tmpdir/bin" "$tmpdir/runtime/images"
  printf 'template-image' > "$tmpdir/runtime/images/ubuntu-template.raw"

  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then
  if [[ -n "${FC_TEST_SUDO_ACTIVE:-}" ]]; then
    printf '0\n'
  else
    printf '1000\n'
  fi
else
  /usr/bin/id "$@"
fi
EOF
  chmod +x "$tmpdir/bin/id"

  cat > "$tmpdir/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$sudo_log"
if [[ "\${1:-}" == '-n' ]]; then
  shift
fi
export FC_TEST_SUDO_ACTIVE=1
exec "\$@"
EOF
  chmod +x "$tmpdir/bin/sudo"

  cat > "$tmpdir/bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == 'resize' ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$tmpdir/bin/qemu-img"

  cat > "$tmpdir/bin/resize2fs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/resize2fs"

  # Stub mount/umount for seed injection into rootfs
  cat > "$tmpdir/bin/mount" <<EOF
#!/usr/bin/env bash
# Create the mount target to simulate a loop mount
mkdir -p "\$3"
exit 0
EOF
  chmod +x "$tmpdir/bin/mount"

  cat > "$tmpdir/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/umount"

  printf '%s\n' '#cloud-config' > "$tmpdir/runtime/images/ubuntu-template-user-data.yaml"

  PATH="$tmpdir/bin:$PATH" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" || return 1

  [[ "$(sed -n '1p' "$sudo_log")" == "-n $REPO_ROOT/bin/fc-create testvm --disk-size 20G --guest-user testuser --ssh-key ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" ]] || fail "fc-create did not re-exec through passwordless sudo for operator flow"
  [[ -f "$metadata_path" ]] || fail "fc-create did not create instance metadata after sudo re-exec"
)

test_instance_seed_uses_template_cloud_init_content() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir user_data_path meta_data_path disk_path mount_target
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/images" "$tmpdir/vms/testvm" "$tmpdir/templates"
  user_data_path="$tmpdir/vms/testvm/user-data"
  meta_data_path="$tmpdir/vms/testvm/meta-data"
  disk_path="$tmpdir/vms/testvm/rootfs.raw"
  mount_target="$tmpdir/mount-target"
  printf 'fake-rootfs' > "$disk_path"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_templates_dir() { printf '%s\n' "$tmpdir/templates"; }
  # Place cloud-init templates with placeholder tokens
  cp "$REPO_ROOT/templates/cloud-init-user-data.yaml" "$tmpdir/templates/"
  cp "$REPO_ROOT/templates/cloud-init-meta-data.yaml" "$tmpdir/templates/"

  # Mock mktemp to return a predictable mount point
  mktemp() {
    if [[ "${1:-}" == "-d" ]]; then
      mkdir -p "$mount_target"
      printf '%s\n' "$mount_target"
      return 0
    fi
    command mktemp "$@"
  }
  mount() { return 0; }
  umount() { return 0; }
  rmdir() { return 0; }

  fc_image_create_instance_seed "testvm" "$disk_path" "seeduser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestSeed user@test" || return 1

  # Verify reference copies in the instance directory
  [[ -f "$user_data_path" ]] || fail "instance user-data reference copy missing"
  grep -q '^  - name: seeduser$' "$user_data_path" || fail "instance user-data missing guest user"
  grep -qF 'sudo: ALL=(ALL) NOPASSWD:ALL' "$user_data_path" || fail "instance user-data missing passwordless sudo"
  grep -q 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestSeed user@test' "$user_data_path" || fail "instance user-data missing ssh key"
  grep -q '^instance-id: testvm$' "$meta_data_path" || fail "instance meta-data missing instance-id"
  grep -q '^local-hostname: testvm$' "$meta_data_path" || fail "instance meta-data missing local-hostname"

  # Verify seed files were injected into the (mocked) mount point
  [[ -f "$mount_target/var/lib/cloud/seed/nocloud/user-data" ]] || fail "seed user-data not injected into rootfs"
  [[ -f "$mount_target/var/lib/cloud/seed/nocloud/meta-data" ]] || fail "seed meta-data not injected into rootfs"
  grep -q '^  - name: seeduser$' "$mount_target/var/lib/cloud/seed/nocloud/user-data" || fail "injected user-data missing guest user"
  grep -q '^instance-id: testvm$' "$mount_target/var/lib/cloud/seed/nocloud/meta-data" || fail "injected meta-data missing instance-id"
)

test_instance_creation_rejects_vm_names_with_overlong_tap_names() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir vm_name

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/images"
  printf 'template-image' > "$tmpdir/images/ubuntu-template.raw"
  vm_name='abcdefghijkl'

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_raw_path() { printf '%s\n' "$tmpdir/images/ubuntu-template.raw"; }
  fc_has_free_space_mib() { return 0; }
  qemu-img() { return 0; }
  resize2fs() { return 0; }

  if fc_image_create_instance_disk "$vm_name" "20G" "testuser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test"; then
    fail "instance creation unexpectedly accepted a VM name with an overlong tap name"
  fi

  [[ ! -d "$tmpdir/vms/$vm_name" ]] || fail "instance directory created for overlong tap name"
)

test_runtime_networking_rolls_back_tap_on_attach_failure() (
  local tmpdir metadata_path ip_log

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/vms/testvm"
  metadata_path="$tmpdir/vms/testvm/vm.env"
  ip_log="$tmpdir/ip.log"

  source "$REPO_ROOT/lib/network.sh"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  ip() {
    printf '%s\n' "$*" >> "$ip_log"
    if [[ "$*" == 'link set fc-testvm0 master vmbr0' ]]; then
      return 1
    fi

    return 0
  }

  if fc_network_create_instance_tap "testvm" "$metadata_path"; then
    fail "live tap setup unexpectedly succeeded during attach failure"
  fi

  grep -q '^tuntap add dev fc-testvm0 mode tap$' "$ip_log" || fail "tap creation command missing or incorrect"
  grep -q '^link set fc-testvm0 master vmbr0$' "$ip_log" || fail "bridge attach command missing or incorrect"
  grep -q '^link delete fc-testvm0$' "$ip_log" || fail "tap rollback delete command missing after attach failure"
  [[ ! -f "$metadata_path" ]] || fail "network metadata should not be written after failed live tap setup"
)

test_runtime_networking_rolls_back_tap_on_metadata_write_failure() (
  local tmpdir metadata_path ip_log

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/vms/testvm"
  metadata_path="$tmpdir/vms/testvm/vm.env"
  ip_log="$tmpdir/ip.log"

  source "$REPO_ROOT/lib/network.sh"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  ip() {
    printf '%s\n' "$*" >> "$ip_log"
    return 0
  }
  fc_network_write_instance_metadata() {
    return 1
  }

  if fc_network_create_instance_tap "testvm" "$metadata_path"; then
    fail "live tap setup unexpectedly succeeded during metadata write failure"
  fi

  grep -q '^tuntap add dev fc-testvm0 mode tap$' "$ip_log" || fail "tap creation command missing or incorrect"
  grep -q '^link set fc-testvm0 master vmbr0$' "$ip_log" || fail "bridge attach command missing or incorrect"
  grep -q '^link set fc-testvm0 up$' "$ip_log" || fail "tap up command missing or incorrect"
  grep -q '^link delete fc-testvm0$' "$ip_log" || fail "tap rollback delete command missing after metadata write failure"
  [[ ! -f "$metadata_path" ]] || fail "network metadata should not exist after failed metadata write"
)

test_fc_create_writes_vcpu_and_memory_to_metadata() (
  local tmpdir metadata_path

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/images"
  printf 'template-image' > "$tmpdir/images/ubuntu-template.raw"
  metadata_path="$tmpdir/vms/testvm/vm.env"

  source "$REPO_ROOT/lib/image.sh"
  source "$REPO_ROOT/lib/network.sh"

  fc_info() { :; }
  fc_warn() { :; }
  fc_ok() { :; }
  fc_error() { :; }
  fc_vm_instances_dir() { printf '%s\n' "$tmpdir/vms"; }
  fc_image_raw_path() { printf '%s\n' "$tmpdir/images/ubuntu-template.raw"; }
  fc_image_user_data_path() { printf '%s\n' "$tmpdir/images/ubuntu-template-user-data.yaml"; }
  fc_has_free_space_mib() { return 0; }
  qemu-img() { return 0; }
  resize2fs() { return 0; }
  fc_image_create_instance_seed() { return 0; }

  printf '%s\n' '#cloud-config' > "$tmpdir/images/ubuntu-template-user-data.yaml"

  fc_image_create_instance_disk "testvm" "20G" "testuser" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" || return 1
  fc_network_prepare_instance_metadata "testvm" "$metadata_path" || return 1

  # Simulate what fc-create does: append compute metadata
  cat >> "$metadata_path" <<EOF
VCPU_COUNT=2
MEM_SIZE_MIB=2048
EOF

  grep -q '^VCPU_COUNT=2$' "$metadata_path" || fail "metadata missing VCPU_COUNT=2"
  grep -q '^MEM_SIZE_MIB=2048$' "$metadata_path" || fail "metadata missing MEM_SIZE_MIB=2048"
)

test_fc_create_defaults_vcpu_and_memory_when_omitted() (
  local tmpdir metadata_path output_file status

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/runtime/images"
  printf 'template-image' > "$tmpdir/runtime/images/ubuntu-template.raw"
  printf '%s\n' '#cloud-config' > "$tmpdir/runtime/images/ubuntu-template-user-data.yaml"
  metadata_path="$tmpdir/runtime/vms/testvm/vm.env"

  # Stub binaries
  mkdir -p "$tmpdir/bin"

  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then printf '0\n'; else /usr/bin/id "$@"; fi
EOF
  chmod +x "$tmpdir/bin/id"

  cat > "$tmpdir/bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/qemu-img"

  cat > "$tmpdir/bin/resize2fs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/resize2fs"

  cat > "$tmpdir/bin/mount" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$3" 2>/dev/null; exit 0
EOF
  chmod +x "$tmpdir/bin/mount"

  cat > "$tmpdir/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/umount"

  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" > "$output_file" 2>&1
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "fc-create failed when --vcpus/--memory omitted: $(cat "$output_file")"
  [[ -f "$metadata_path" ]] || fail "vm.env not created when defaults used"
  grep -q '^VCPU_COUNT=1$' "$metadata_path" || fail "default VCPU_COUNT should be 1"
  grep -q '^MEM_SIZE_MIB=1024$' "$metadata_path" || fail "default MEM_SIZE_MIB should be 1024"
)

test_fc_create_rejects_invalid_vcpu_values() (
  local tmpdir output_file status

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then printf '0\n'; else /usr/bin/id "$@"; fi
EOF
  chmod +x "$tmpdir/bin/id"

  # Test --vcpus 0
  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" --vcpus 0 < /dev/null > "$output_file" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "fc-create should reject --vcpus 0"

  # Test --vcpus abc
  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" --vcpus abc < /dev/null > "$output_file" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "fc-create should reject --vcpus abc"
)

test_fc_create_rejects_memory_below_minimum() (
  local tmpdir output_file status

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then printf '0\n'; else /usr/bin/id "$@"; fi
EOF
  chmod +x "$tmpdir/bin/id"

  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" --memory 64m < /dev/null > "$output_file" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "fc-create should reject --memory 64m (below 128 MiB minimum)"
)

test_fc_create_normalizes_memory_gib_to_mib() (
  local tmpdir metadata_path output_file status

  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/runtime/images"
  printf 'template-image' > "$tmpdir/runtime/images/ubuntu-template.raw"
  printf '%s\n' '#cloud-config' > "$tmpdir/runtime/images/ubuntu-template-user-data.yaml"
  metadata_path="$tmpdir/runtime/vms/testvm/vm.env"

  # Stub binaries
  mkdir -p "$tmpdir/bin"

  cat > "$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then printf '0\n'; else /usr/bin/id "$@"; fi
EOF
  chmod +x "$tmpdir/bin/id"

  cat > "$tmpdir/bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/qemu-img"

  cat > "$tmpdir/bin/resize2fs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/resize2fs"

  cat > "$tmpdir/bin/mount" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$3" 2>/dev/null; exit 0
EOF
  chmod +x "$tmpdir/bin/mount"

  cat > "$tmpdir/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmpdir/bin/umount"

  output_file=$(mktemp)
  set +e
  PATH="$tmpdir/bin:$PATH" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    bash "$REPO_ROOT/bin/fc-create" testvm --disk-size 20G --guest-user testuser --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@test" --memory 2g > "$output_file" 2>&1
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "fc-create failed with --memory 2g: $(cat "$output_file")"
  [[ -f "$metadata_path" ]] || fail "vm.env not created with --memory 2g"
  grep -q '^MEM_SIZE_MIB=2048$' "$metadata_path" || fail "2g should normalize to MEM_SIZE_MIB=2048"
)

test_network_resolve_guest_ip_finds_mac_in_neighbor_table() (
    source "$REPO_ROOT/lib/network.sh"

    fc_info() { :; }
    fc_warn() { :; }
    fc_ok() { :; }
    fc_error() { :; }

    ip() {
        if [[ "$1" == "neigh" && "$2" == "show" ]]; then
            printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
            printf '192.168.1.108 dev vmbr0 lladdr 02:aa:bb:cc:dd:ee STALE\n'
            return 0
        fi
        return 1
    }

    local result
    result=$(fc_network_resolve_guest_ip "02:18:8c:c0:a7:f8" "vmbr0") || fail "resolve_guest_ip failed for known MAC"
    [[ "$result" == "192.168.1.107" ]] || fail "resolve_guest_ip returned '$result' instead of 192.168.1.107"
)

test_network_resolve_guest_ip_returns_failure_for_unknown_mac() (
    source "$REPO_ROOT/lib/network.sh"

    fc_info() { :; }
    fc_warn() { :; }
    fc_ok() { :; }
    fc_error() { :; }

    ip() {
        if [[ "$1" == "neigh" && "$2" == "show" ]]; then
            printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
            return 0
        fi
        return 1
    }
    arping() { return 1; }

    if fc_network_resolve_guest_ip "02:ff:ff:ff:ff:ff" "vmbr0"; then
        fail "resolve_guest_ip unexpectedly succeeded for unknown MAC"
    fi
)

test_format_uptime_formats_seconds_correctly() (
    source "$REPO_ROOT/lib/common.sh"

    [[ "$(fc_format_uptime 90061)" == "1d 1h 1m" ]] || fail "uptime 90061s did not format as 1d 1h 1m"
    [[ "$(fc_format_uptime 3661)" == "1h 1m" ]] || fail "uptime 3661s did not format as 1h 1m"
    [[ "$(fc_format_uptime 300)" == "5m" ]] || fail "uptime 300s did not format as 5m"
    [[ "$(fc_format_uptime 0)" == "0m" ]] || fail "uptime 0s did not format as 0m"
)

main() {
  test_disk_size_parser_accepts_gib_and_mib || return 1
  test_instance_creation_requires_existing_template || return 1
  test_instance_creation_clones_resizes_and_writes_metadata || return 1
  test_instance_creation_rejects_vm_names_with_overlong_tap_names || return 1
  test_fc_create_requires_credentials_in_non_interactive_mode || return 1
  test_fc_create_records_network_identity_metadata_without_live_ip_changes || return 1
  test_fc_create_reexecs_with_sudo_for_operator_flow || return 1
  test_instance_seed_uses_template_cloud_init_content || return 1
  test_runtime_networking_rolls_back_tap_on_attach_failure || return 1
  test_runtime_networking_rolls_back_tap_on_metadata_write_failure || return 1
  test_fc_create_writes_vcpu_and_memory_to_metadata || return 1
  test_fc_create_defaults_vcpu_and_memory_when_omitted || return 1
  test_fc_create_rejects_invalid_vcpu_values || return 1
  test_fc_create_rejects_memory_below_minimum || return 1
  test_fc_create_normalizes_memory_gib_to_mib || return 1
  test_network_resolve_guest_ip_finds_mac_in_neighbor_table || return 1
  test_network_resolve_guest_ip_returns_failure_for_unknown_mac || return 1
  test_format_uptime_formats_seconds_correctly || return 1
  printf 'PASS: instance creation checks\n'
}

main "$@"
