#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_expand_path_resolves_tilde_user_shortcut() (
  source "$REPO_ROOT/lib/image.sh"

  # ~/ should expand to $HOME
  [[ "$(fc_image_expand_path '~/foo/bar')" == "$HOME/foo/bar" ]] || fail "~/ path did not expand to \$HOME"

  # bare path should pass through
  [[ "$(fc_image_expand_path '/absolute/path')" == "/absolute/path" ]] || fail "absolute path was modified"
  [[ "$(fc_image_expand_path 'relative/path')" == "relative/path" ]] || fail "relative path was modified"
)

test_failed_download_does_not_publish_canonical_image() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir keyfile
  tmpdir=$(mktemp -d)
  keyfile="$tmpdir/authorized_keys"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForImageBuild user@test' > "$keyfile"

  fc_info() { :; }
  fc_warn() { :; }
  fc_error() { :; }
  fc_image_template_dir() { printf '%s\n' "$tmpdir/images"; }
  fc_image_download_official_cloud_image() {
    local _url=$1
    local output_path=$2
    printf 'partial-download' > "$output_path"
    return 1
  }

  if fc_image_build_template --ssh-key-file "$keyfile"; then
    fail "download failure unexpectedly succeeded"
  fi

  [[ ! -e "$tmpdir/images/ubuntu-template.img" ]] || fail "partial download reached canonical path"
)

test_failed_convert_does_not_publish_canonical_raw() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir keyfile
  tmpdir=$(mktemp -d)
  keyfile="$tmpdir/authorized_keys"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForImageBuild user@test' > "$keyfile"

  fc_info() { :; }
  fc_warn() { :; }
  fc_error() { :; }
  fc_ok() { :; }
  fc_image_template_dir() { printf '%s\n' "$tmpdir/images"; }
  fc_image_download_official_cloud_image() {
    local _url=$1
    local output_path=$2
    printf 'downloaded-image' > "$output_path"
  }
  fc_image_convert_qcow2_to_raw() {
    local _source_image=$1
    local output_path=$2
    printf 'partial-raw-image' > "$output_path"
    return 1
  }

  if fc_image_build_template --ssh-key-file "$keyfile"; then
    fail "convert failure unexpectedly succeeded"
  fi

  [[ ! -e "$tmpdir/images/ubuntu-template.raw" ]] || fail "partial raw image reached canonical path"
)

test_failed_extraction_does_not_publish_canonical_raw() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir keyfile
  tmpdir=$(mktemp -d)
  keyfile="$tmpdir/authorized_keys"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForImageBuild user@test' > "$keyfile"

  fc_info() { :; }
  fc_warn() { :; }
  fc_error() { :; }
  fc_ok() { :; }
  fc_image_template_dir() { printf '%s\n' "$tmpdir/images"; }
  fc_image_download_official_cloud_image() {
    local _url=$1
    local output_path=$2
    printf 'downloaded-image' > "$output_path"
  }
  fc_image_convert_qcow2_to_raw() {
    local _source_image=$1
    local output_path=$2
    printf 'raw-image' > "$output_path"
  }
  fc_image_extract_rootfs_partition() {
    fc_error "extraction failed"
    return 1
  }

  if fc_image_build_template --ssh-key-file "$keyfile"; then
    fail "extraction failure unexpectedly succeeded"
  fi

  [[ ! -e "$tmpdir/images/ubuntu-template.raw" ]] || fail "partial raw image reached canonical path after extraction failure"
)

test_failed_forced_customization_returns_nonzero_and_no_metadata() (
  local tmpdir keyfile rc
  tmpdir=$(mktemp -d)
  keyfile="$tmpdir/authorized_keys"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForImageBuild user@test' > "$keyfile"

  set +e
  bash -c 'set -eu; repo_root=$1; test_tmpdir=$2; ssh_key_file=$3; source "$repo_root/lib/image.sh"; fc_info(){ :; }; fc_warn(){ :; }; fc_error(){ :; }; fc_ok(){ :; }; fc_image_template_dir(){ printf "%s\n" "$test_tmpdir/images"; }; fc_image_stage_dir(){ mkdir -p "$test_tmpdir/images/.ubuntu-template.build.staged"; printf "%s\n" "$test_tmpdir/images/.ubuntu-template.build.staged"; }; fc_image_download_official_cloud_image(){ local _url=$1; local output_path=$2; printf "downloaded-image" > "$output_path"; }; fc_image_convert_qcow2_to_raw(){ local _source_image=$1; local output_path=$2; printf "raw-image" > "$output_path"; }; fc_image_extract_rootfs_partition(){ local _raw=$1; local output_path=$2; printf "extracted-rootfs" > "$output_path"; }; fc_image_patch_rootfs_for_firecracker(){ :; }; fc_command_exists(){ [[ "$1" == "virt-customize" ]]; }; mktemp(){ if [[ "$#" -eq 1 && "$1" == "-d" ]]; then printf "%s\n" "$test_tmpdir/customize-temp"; mkdir -p "$test_tmpdir/customize-temp"; return 0; fi; command mktemp "$@"; }; virt-customize(){ return 23; }; fc_image_build_template --ssh-key-file "$ssh_key_file" --offline-customize' _ "$REPO_ROOT" "$tmpdir" "$keyfile"
  rc=$?
  set -e

  [[ "$rc" -eq 23 ]] || fail "expected virt-customize exit status 23, got $rc"
  [[ ! -e "$tmpdir/images/ubuntu-template.metadata" ]] || fail "metadata published for failed customization"
  [[ ! -e "$tmpdir/customize-temp" ]] || fail "customization temp dir leaked after failure"
  [[ ! -e "$tmpdir/images/.ubuntu-template.build.staged" ]] || fail "stage dir leaked after failed customization"
)

test_completed_build_metadata_records_actual_customization_result() (
  source "$REPO_ROOT/lib/image.sh"

  local tmpdir keyfile metadata_path
  tmpdir=$(mktemp -d)
  keyfile="$tmpdir/authorized_keys"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyForImageBuild user@test' > "$keyfile"
  metadata_path="$tmpdir/images/ubuntu-template.metadata"

  fc_info() { :; }
  fc_warn() { :; }
  fc_error() { :; }
  fc_ok() { :; }
  fc_image_template_dir() { printf '%s\n' "$tmpdir/images"; }
  fc_image_download_official_cloud_image() {
    local _url=$1
    local output_path=$2
    printf 'downloaded-image' > "$output_path"
  }
  fc_image_convert_qcow2_to_raw() {
    local _source_image=$1
    local output_path=$2
    printf 'raw-image' > "$output_path"
  }
  fc_image_extract_rootfs_partition() {
    local _raw=$1
    local output_path=$2
    printf 'extracted-rootfs' > "$output_path"
  }
  fc_image_patch_rootfs_for_firecracker() {
    :
  }
  fc_command_exists() {
    return 1
  }

  fc_image_build_template --ssh-key-file "$keyfile" || return 1

  [[ -f "$metadata_path" ]] || fail "metadata file missing after successful build"
  grep -q '^offline_customization_requested=auto$' "$metadata_path" || fail "metadata missing requested customization mode"
  grep -q '^offline_customization_result=skipped-unavailable$' "$metadata_path" || fail "metadata missing actual customization result"
  grep -q '^build_status=complete$' "$metadata_path" || fail "metadata missing completed build status"
)

main() {
  test_expand_path_resolves_tilde_user_shortcut || return 1
  test_failed_download_does_not_publish_canonical_image || return 1
  test_failed_convert_does_not_publish_canonical_raw || return 1
  test_failed_extraction_does_not_publish_canonical_raw || return 1
  test_failed_forced_customization_returns_nonzero_and_no_metadata || return 1
  test_completed_build_metadata_records_actual_customization_result || return 1
  printf 'PASS: image build checks\n'
}

main "$@"
