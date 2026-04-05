#!/usr/bin/env bash

if [[ -n "${FC_IMAGE_SH_LOADED:-}" ]]; then
  return 0
fi
readonly FC_IMAGE_SH_LOADED=1

# shellcheck source=./common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck source=./network.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/network.sh"
fc_load_config

readonly FC_IMAGE_TEMPLATE_NAME="ubuntu-template"
# Default SSH key file is now read from FC_SSH_KEY_FILE (set in config.sh).
FC_IMAGE_DEFAULT_SSH_KEY_FILE="${FC_SSH_KEY_FILE:-$HOME/.ssh/authorized_keys}"
FC_IMAGE_LAST_CUSTOMIZATION_RESULT=

fc_image_template_dir() {
  printf '%s/images\n' "$FC_RUNTIME_ROOT"
}

fc_image_templates_dir() {
  printf '%s/templates\n' "$(fc_repo_root)"
}

fc_image_ubuntu_release() {
  printf '%s\n' "${FC_UBUNTU_RELEASE:-noble}"
}

fc_image_ubuntu_cloud_image_url() {
  local release
  release=$(fc_image_ubuntu_release)
  printf '%s\n' "${FC_UBUNTU_CLOUD_IMAGE_URL:-https://cloud-images.ubuntu.com/${release}/current/${release}-server-cloudimg-amd64.img}"
}

fc_image_download_path() {
  printf '%s/%s.img\n' "$(fc_image_template_dir)" "$FC_IMAGE_TEMPLATE_NAME"
}

fc_image_raw_path() {
  printf '%s/%s.raw\n' "$(fc_image_template_dir)" "$FC_IMAGE_TEMPLATE_NAME"
}

fc_image_user_data_path() {
  printf '%s/%s-user-data.yaml\n' "$(fc_image_template_dir)" "$FC_IMAGE_TEMPLATE_NAME"
}

fc_image_meta_data_path() {
  printf '%s/%s-meta-data.yaml\n' "$(fc_image_template_dir)" "$FC_IMAGE_TEMPLATE_NAME"
}

fc_image_metadata_path() {
  printf '%s/%s.metadata\n' "$(fc_image_template_dir)" "$FC_IMAGE_TEMPLATE_NAME"
}

fc_image_stage_dir() {
  local template_dir=$1
  mktemp -d "$template_dir/.${FC_IMAGE_TEMPLATE_NAME}.build.XXXXXX"
}

fc_image_stage_file_path() {
  local stage_dir=$1
  local final_path=$2
  printf '%s/%s\n' "$stage_dir" "$(basename -- "$final_path")"
}

fc_image_default_ssh_key_file() {
  printf '%s\n' "$FC_IMAGE_DEFAULT_SSH_KEY_FILE"
}

fc_image_expand_path() {
  local path=$1

  case "$path" in
    "~"/*)
      printf '%s/%s\n' "$HOME" "${path#"~/"}"
      ;;
    "~"*/*)
      local user=${path%%/*}
      user=${user#"~"}
      local rest=${path#*/}
      if [[ -d "/home/$user" ]]; then
        printf '/home/%s/%s\n' "$user" "$rest"
      else
        printf '%s\n' "$path"
      fi
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

fc_image_read_ssh_public_key() {
  local ssh_key_file=$1
  local line=

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done < "$ssh_key_file"

  fc_error "SSH key file is empty: $ssh_key_file"
  return 1
}

fc_image_apply_template() {
  local template_path=$1
  local output_path=$2
  local rendered

  rendered=$(<"$template_path") || return 1
  shift 2

  while [[ $# -gt 1 ]]; do
    rendered=${rendered//"$1"/$2}
    shift 2
  done

  printf '%s\n' "$rendered" > "$output_path"
}

fc_image_render_user_data() {
  local ssh_public_key=$1
  local output_path=$2

  fc_image_apply_template \
    "$(fc_image_templates_dir)/cloud-init-user-data.yaml" \
    "$output_path" \
    "__FC_GUEST_USER__" "$FC_GUEST_USER" \
    "__FC_SSH_AUTHORIZED_KEY__" "$ssh_public_key"
}

fc_image_render_meta_data() {
  local instance_id=$1
  local local_hostname=$2
  local output_path=$3

  fc_image_apply_template \
    "$(fc_image_templates_dir)/cloud-init-meta-data.yaml" \
    "$output_path" \
    "__FC_INSTANCE_ID__" "$instance_id" \
    "__FC_LOCAL_HOSTNAME__" "$local_hostname"
}

fc_image_render_nocloud_seed() {
  local ssh_key_file=$1
  local user_data_path=$2
  local meta_data_path=$3
  local instance_id=${4:-$FC_IMAGE_TEMPLATE_NAME}
  local local_hostname=${5:-$FC_IMAGE_TEMPLATE_NAME}
  local ssh_public_key

  ssh_public_key=$(fc_image_read_ssh_public_key "$ssh_key_file") || return 1
  fc_image_render_user_data "$ssh_public_key" "$user_data_path" || return 1
  fc_image_render_meta_data "$instance_id" "$local_hostname" "$meta_data_path"
}

fc_image_ensure_template_dir() {
  mkdir -p "$(fc_image_template_dir)"
}

fc_image_download_official_cloud_image() {
  local download_url=$1
  local output_path=$2

  fc_info "Downloading Ubuntu cloud image: $download_url"
  curl -fL --retry 3 --output "$output_path" "$download_url"
}

fc_image_convert_qcow2_to_raw() {
  local source_image=$1
  local output_path=$2

  fc_info "Converting cloud image to raw template: $output_path"
  qemu-img convert -f qcow2 -O raw "$source_image" "$output_path"
}

fc_image_extract_rootfs_partition() {
  local raw_image=$1
  local output_path=$2
  local partition_number=${3:-1}
  local sfdisk_output start_sector sector_count

  fc_info "Extracting partition $partition_number from GPT image as standalone rootfs"

  sfdisk_output=$(sfdisk --dump "$raw_image") || {
    fc_error "sfdisk --dump failed on $raw_image"
    return 1
  }

  # Parse sfdisk dump output. Lines look like:
  #   /path/to/image1 : start=     2048, size=  5240832, type=..., uuid=...
  # We match the line ending in the partition number (image1 for partition 1).
  local line
  line=$(printf '%s\n' "$sfdisk_output" | grep "${raw_image}${partition_number} *:")
  if [[ -z "$line" ]]; then
    fc_error "partition $partition_number not found in sfdisk output for $raw_image"
    return 1
  fi

  start_sector=$(printf '%s\n' "$line" | sed -n 's/.*start= *\([0-9]*\).*/\1/p')
  sector_count=$(printf '%s\n' "$line" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')

  if [[ -z "$start_sector" || -z "$sector_count" ]]; then
    fc_error "could not parse start/size from sfdisk output for partition $partition_number"
    return 1
  fi

  fc_info "Partition $partition_number: start=$start_sector sectors, size=$sector_count sectors ($(( sector_count * 512 / 1024 / 1024 )) MiB)"

  dd if="$raw_image" of="$output_path" bs=512 skip="$start_sector" count="$sector_count" status=progress || {
    fc_error "dd extraction of partition $partition_number failed"
    return 1
  }

  fc_ok "Extracted rootfs partition ($((sector_count * 512 / 1024 / 1024)) MiB)"
}

fc_image_patch_rootfs_for_firecracker() {
  local rootfs_image=$1
  local mount_dir

  fc_info "Patching extracted rootfs for Firecracker (fstab, etc.)"

  mount_dir=$(mktemp -d) || return 1

  if ! mount -o loop "$rootfs_image" "$mount_dir"; then
    fc_error "failed to loop-mount rootfs for patching"
    rmdir "$mount_dir"
    return 1
  fi

  # The Ubuntu cloud image fstab references BOOT and UEFI partitions that
  # no longer exist in the extracted single-partition rootfs.  Comment them
  # out so systemd does not block boot waiting for missing devices.
  if [[ -f "$mount_dir/etc/fstab" ]]; then
    sed -i '/LABEL=BOOT/s/^/#/' "$mount_dir/etc/fstab"
    sed -i '/LABEL=UEFI/s/^/#/' "$mount_dir/etc/fstab"
    sed -i '/LABEL=cloudimg-rootfs/s/^/#/' "$mount_dir/etc/fstab"
    fc_info "Patched /etc/fstab: commented out BOOT, UEFI, and cloudimg-rootfs entries"
  fi

  umount "$mount_dir" || {
    fc_error "failed to unmount rootfs after patching"
    return 1
  }
  rmdir "$mount_dir"

  fc_ok "Rootfs patched for Firecracker"
}

fc_image_write_metadata() {
  local metadata_path=$1
  local download_url=$2
  local downloaded_image=$3
  local raw_image=$4
  local user_data_path=$5
  local meta_data_path=$6
  local ssh_key_file=$7
  local customization_requested=$8
  local customization_result=$9

  cat > "$metadata_path" <<EOF
template_name=$FC_IMAGE_TEMPLATE_NAME
ubuntu_release=$(fc_image_ubuntu_release)
source_url=$download_url
downloaded_image=$downloaded_image
raw_template_image=$raw_image
user_data=$user_data_path
meta_data=$meta_data_path
ssh_key_file=$ssh_key_file
build_timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
offline_customization_requested=$customization_requested
offline_customization_result=$customization_result
build_status=complete
EOF
}

fc_image_publish_file() {
  local staged_path=$1
  local final_path=$2
  mv -f "$staged_path" "$final_path"
}

fc_image_publish_staged_outputs() {
  local staged_downloaded_image=$1
  local downloaded_image=$2
  local staged_raw_image=$3
  local raw_image=$4
  local staged_user_data_path=$5
  local user_data_path=$6
  local staged_meta_data_path=$7
  local meta_data_path=$8
  local staged_metadata_path=$9
  local metadata_path=${10}

  fc_image_publish_file "$staged_downloaded_image" "$downloaded_image" || return 1
  fc_image_publish_file "$staged_raw_image" "$raw_image" || return 1
  fc_image_publish_file "$staged_user_data_path" "$user_data_path" || return 1
  fc_image_publish_file "$staged_meta_data_path" "$meta_data_path" || return 1
  fc_image_publish_file "$staged_metadata_path" "$metadata_path"
}

fc_image_instance_dir() {
  local vm_name=$1
  printf '%s/%s\n' "$(fc_vm_instances_dir)" "$vm_name"
}

fc_image_instance_disk_path() {
  local vm_name=$1
  printf '%s/rootfs.raw\n' "$(fc_image_instance_dir "$vm_name")"
}

fc_image_instance_metadata_path() {
  local vm_name=$1
  printf '%s/vm.env\n' "$(fc_image_instance_dir "$vm_name")"
}

fc_image_instance_user_data_path() {
  local vm_name=$1
  printf '%s/user-data\n' "$(fc_image_instance_dir "$vm_name")"
}

fc_image_instance_meta_data_path() {
  local vm_name=$1
  printf '%s/meta-data\n' "$(fc_image_instance_dir "$vm_name")"
}

fc_image_instance_seed_path() {
  local vm_name=$1
  printf '%s/seed.img\n' "$(fc_image_instance_dir "$vm_name")"
}

fc_image_env_get() {
  local metadata_path=$1
  local key=$2

  awk -F= -v key="$key" '$1 == key { sub($1 FS, "", $0); value=$0 } END { if (value != "") print value }' "$metadata_path"
}

fc_image_template_user_data_path() {
  local metadata_path user_data_path

  metadata_path=$(fc_image_metadata_path)
  if [[ -f "$metadata_path" ]]; then
    user_data_path=$(fc_image_env_get "$metadata_path" user_data) || return 1
    if [[ -n "$user_data_path" ]]; then
      printf '%s\n' "$user_data_path"
      return 0
    fi
  fi

  fc_image_user_data_path
}

fc_image_create_instance_seed() {
  local vm_name=$1
  local disk_path=$2
  local template_user_data_path user_data_path meta_data_path mount_dir

  template_user_data_path=$(fc_image_expand_path "$(fc_image_template_user_data_path)") || return 1
  user_data_path=$(fc_image_instance_user_data_path "$vm_name")
  meta_data_path=$(fc_image_instance_meta_data_path "$vm_name")

  [[ -f "$template_user_data_path" ]] || {
    fc_error "template user-data not found: $template_user_data_path"
    return 1
  }

  # Keep copies in the instance dir for reference / debugging
  cp -- "$template_user_data_path" "$user_data_path" || return 1
  fc_image_render_meta_data "$vm_name" "$vm_name" "$meta_data_path" || return 1

  # Inject cloud-init seed directly into the rootfs so the NoCloud
  # datasource finds it without needing a separate seed drive (the
  # Firecracker CI kernel lacks iso9660 and vfat built-in).
  mount_dir=$(mktemp -d) || return 1
  if ! mount -o loop "$disk_path" "$mount_dir"; then
    fc_error "failed to loop-mount instance disk for seed injection"
    rmdir "$mount_dir"
    return 1
  fi

  mkdir -p "$mount_dir/var/lib/cloud/seed/nocloud" || {
    umount "$mount_dir"; rmdir "$mount_dir"; return 1
  }
  cp -- "$user_data_path"  "$mount_dir/var/lib/cloud/seed/nocloud/user-data" || {
    umount "$mount_dir"; rmdir "$mount_dir"; return 1
  }
  cp -- "$meta_data_path"  "$mount_dir/var/lib/cloud/seed/nocloud/meta-data" || {
    umount "$mount_dir"; rmdir "$mount_dir"; return 1
  }

  umount "$mount_dir" || {
    fc_error "failed to unmount instance disk after seed injection"
    return 1
  }
  rmdir "$mount_dir"

  fc_info "Injected NoCloud seed into rootfs for VM $vm_name"
}

fc_image_validate_vm_name() {
  local vm_name=$1

  if [[ "$vm_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
    return 0
  fi

  fc_error "invalid VM name '$vm_name'; use lowercase letters, digits, and hyphens, starting with a letter"
  return 1
}

fc_image_prompt_disk_size() {
  local response=

  printf 'Disk size [%s]: ' "$FC_DEFAULT_DISK_SIZE" >&2
  IFS= read -r response || return 1

  if [[ -z "$response" ]]; then
    response=$FC_DEFAULT_DISK_SIZE
  fi

  printf '%s\n' "$response"
}

fc_image_require_free_space_for_disk() {
  local parent_dir=$1
  local disk_size=$2
  local required_mib

  required_mib=$(fc_size_to_mib "$disk_size") || return 1

  if fc_has_free_space_mib "$parent_dir" "$required_mib"; then
    return 0
  fi

  fc_error "$parent_dir does not have enough free space for disk size $disk_size"
  return 1
}

fc_image_write_instance_metadata() {
  local metadata_path=$1
  local vm_name=$2
  local disk_size=$3
  local template_path=$4
  local disk_path=$5

  cat > "$metadata_path" <<EOF
VM_NAME=$vm_name
INSTANCE_DIR=$(dirname -- "$metadata_path")
DISK_SIZE=$disk_size
ROOTFS_FILENAME=$(basename -- "$disk_path")
ROOTFS_PATH=$disk_path
TEMPLATE_PATH=$template_path
CREATED_AT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

fc_image_clone_template() {
  local template_path=$1
  local disk_path=$2

  cp -- "$template_path" "$disk_path"
}

fc_image_resize_instance_disk() {
  local disk_path=$1
  local disk_size=$2

  qemu-img resize "$disk_path" "$disk_size" || return 1

  # The template is a bare ext4 filesystem (no partition table), so
  # resize2fs is needed to grow the filesystem to fill the new size.
  # -f forces resize even when e2fsck has not been run recently.
  fc_info "Expanding ext4 filesystem to fill $disk_size"
  resize2fs -f "$disk_path"
}

fc_image_create_instance_disk() {
  local vm_name=$1
  local disk_size=$2
  local template_path
  local instance_dir
  local disk_path
  local metadata_path
  local parent_dir

  fc_image_validate_vm_name "$vm_name" || return 1
  fc_network_validate_vm_name "$vm_name" || return 1
  fc_size_to_mib "$disk_size" >/dev/null || return 1

  template_path=$(fc_image_raw_path)
  if [[ ! -f "$template_path" ]]; then
    fc_error "template image not found: $template_path"
    return 1
  fi

  instance_dir=$(fc_image_instance_dir "$vm_name")
  disk_path=$(fc_image_instance_disk_path "$vm_name")
  metadata_path=$(fc_image_instance_metadata_path "$vm_name")
  parent_dir=$(dirname -- "$(fc_vm_instances_dir)")

  if [[ -e "$instance_dir" ]]; then
    fc_error "instance already exists: $instance_dir"
    return 1
  fi

  mkdir -p "$(fc_vm_instances_dir)"
  fc_image_require_free_space_for_disk "$parent_dir" "$disk_size" || return 1

  mkdir -p "$instance_dir"
  if ! fc_image_clone_template "$template_path" "$disk_path"; then
    rm -rf "$instance_dir"
    return 1
  fi

  if ! fc_image_resize_instance_disk "$disk_path" "$disk_size"; then
    rm -rf "$instance_dir"
    return 1
  fi

  if ! fc_image_create_instance_seed "$vm_name" "$disk_path"; then
    rm -rf "$instance_dir"
    return 1
  fi

  if ! fc_image_write_instance_metadata "$metadata_path" "$vm_name" "$disk_size" "$template_path" "$disk_path"; then
    rm -rf "$instance_dir"
    return 1
  fi

  fc_ok "Created persistent disk for VM $vm_name"
}

fc_image_maybe_customize_raw_template() {
  local raw_image=$1
  local customization_mode=${2:-auto}
  local customize_requested=0
  local temp_dir=
  local status=0

  FC_IMAGE_LAST_CUSTOMIZATION_RESULT=

  if [[ "$customization_mode" == "never" ]]; then
    fc_info "Skipping offline image customization"
    FC_IMAGE_LAST_CUSTOMIZATION_RESULT="skipped-by-flag"
    return 0
  fi

  if [[ "$customization_mode" == "always" ]]; then
    customize_requested=1
  fi

  if ! fc_command_exists virt-customize; then
    if [[ "$customize_requested" -eq 1 ]]; then
      fc_error "virt-customize is required when offline customization is forced"
      return 1
    fi

    fc_warn "virt-customize not found; leaving the raw template unmodified"
    FC_IMAGE_LAST_CUSTOMIZATION_RESULT="skipped-unavailable"
    return 0
  fi

  temp_dir=$(mktemp -d)
  mkdir -p "$temp_dir/firecracker"
  printf 'template_name=%s\n' "$FC_IMAGE_TEMPLATE_NAME" > "$temp_dir/firecracker/template-build.metadata"

  fc_info "Applying optional offline customization metadata"
  if virt-customize \
    -a "$raw_image" \
    --mkdir /etc/firecracker \
    --copy-in "$temp_dir/firecracker:/etc"; then
    status=0
  else
    status=$?
  fi

  rm -rf "$temp_dir"

  if [[ "$status" -ne 0 ]]; then
    return "$status"
  fi

  FC_IMAGE_LAST_CUSTOMIZATION_RESULT="applied"
}

fc_image_build_template_usage() {
  cat <<EOF
Usage: fc_image_build_template [--ssh-key-file PATH] [--offline-customize|--skip-customize]

Builds the Ubuntu template image assets under $(fc_image_template_dir).
Default SSH key source: $(fc_image_default_ssh_key_file)
EOF
}

fc_image_build_template() {
  local ssh_key_file
  local customization_mode=auto
  local download_url
  local downloaded_image
  local raw_image
  local user_data_path
  local meta_data_path
  local metadata_path
  local stage_dir
  local staged_downloaded_image
  local staged_raw_image
  local staged_user_data_path
  local staged_meta_data_path
  local staged_metadata_path
  local customization_result
  local customization_status

  ssh_key_file=$(fc_image_default_ssh_key_file)

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssh-key-file)
        if [[ $# -lt 2 ]]; then
          fc_error "--ssh-key-file requires a path argument"
          return 1
        fi
        ssh_key_file=$2
        shift 2
        ;;
      --offline-customize)
        customization_mode=always
        shift
        ;;
      --skip-customize)
        customization_mode=never
        shift
        ;;
      --help|-h)
        fc_image_build_template_usage
        return 0
        ;;
      *)
        fc_error "Unknown argument: $1"
        fc_image_build_template_usage >&2
        return 1
        ;;
    esac
  done

  ssh_key_file=$(fc_image_expand_path "$ssh_key_file")
  if [[ ! -f "$ssh_key_file" ]]; then
    fc_error "SSH key file not found: $ssh_key_file"
    return 1
  fi

  download_url=$(fc_image_ubuntu_cloud_image_url)
  downloaded_image=$(fc_image_download_path)
  raw_image=$(fc_image_raw_path)
  user_data_path=$(fc_image_user_data_path)
  meta_data_path=$(fc_image_meta_data_path)
  metadata_path=$(fc_image_metadata_path)

  fc_image_ensure_template_dir || return 1
  stage_dir=$(fc_image_stage_dir "$(fc_image_template_dir)") || return 1
  staged_downloaded_image=$(fc_image_stage_file_path "$stage_dir" "$downloaded_image")
  staged_raw_image=$(fc_image_stage_file_path "$stage_dir" "$raw_image")
  staged_user_data_path=$(fc_image_stage_file_path "$stage_dir" "$user_data_path")
  staged_meta_data_path=$(fc_image_stage_file_path "$stage_dir" "$meta_data_path")
  staged_metadata_path=$(fc_image_stage_file_path "$stage_dir" "$metadata_path")

  if ! fc_image_download_official_cloud_image "$download_url" "$staged_downloaded_image"; then
    rm -rf "$stage_dir"
    return 1
  fi

  if ! fc_image_convert_qcow2_to_raw "$staged_downloaded_image" "$staged_raw_image"; then
    rm -rf "$stage_dir"
    return 1
  fi

  # Firecracker CI kernels have a compiled-in root=/dev/vda which expects a
  # bare filesystem (not a GPT-partitioned disk).  Extract partition 1 from the
  # Ubuntu cloud image so the rootfs template is a standalone ext4 filesystem.
  local staged_full_disk="${staged_raw_image}.full-disk"
  mv "$staged_raw_image" "$staged_full_disk" || {
    rm -rf "$stage_dir"
    return 1
  }
  if ! fc_image_extract_rootfs_partition "$staged_full_disk" "$staged_raw_image"; then
    rm -rf "$stage_dir"
    return 1
  fi
  rm -f "$staged_full_disk"

  # Patch the extracted rootfs: comment out fstab entries for partitions
  # (BOOT, UEFI, cloudimg-rootfs) that no longer exist in the bare image.
  if ! fc_image_patch_rootfs_for_firecracker "$staged_raw_image"; then
    rm -rf "$stage_dir"
    return 1
  fi

  if ! fc_image_render_nocloud_seed "$ssh_key_file" "$staged_user_data_path" "$staged_meta_data_path"; then
    rm -rf "$stage_dir"
    return 1
  fi

  if fc_image_maybe_customize_raw_template "$staged_raw_image" "$customization_mode"; then
    customization_status=0
  else
    customization_status=$?
  fi
  if [[ "$customization_status" -ne 0 ]]; then
    rm -rf "$stage_dir"
    return "$customization_status"
  fi
  customization_result=$FC_IMAGE_LAST_CUSTOMIZATION_RESULT

  fc_image_write_metadata \
    "$staged_metadata_path" \
    "$download_url" \
    "$downloaded_image" \
    "$raw_image" \
    "$user_data_path" \
    "$meta_data_path" \
    "$ssh_key_file" \
    "$customization_mode" \
    "$customization_result" || {
      rm -rf "$stage_dir"
      return 1
    }

  if ! fc_image_publish_staged_outputs \
    "$staged_downloaded_image" "$downloaded_image" \
    "$staged_raw_image" "$raw_image" \
    "$staged_user_data_path" "$user_data_path" \
    "$staged_meta_data_path" "$meta_data_path" \
    "$staged_metadata_path" "$metadata_path"; then
    rm -rf "$stage_dir"
    return 1
  fi

  rm -rf "$stage_dir"
}
