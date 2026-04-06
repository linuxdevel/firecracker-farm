#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_resolve_latest_version_emits_clean_tag_only() (
  local tmpdir stub_dir repo_copy resolved_version

  tmpdir=$(mktemp -d)
  stub_dir="$tmpdir/stubs"
  repo_copy="$tmpdir/repo"
  mkdir -p "$stub_dir"
  mkdir -p "$repo_copy/bin" "$repo_copy/lib"

  cp "$REPO_ROOT/bin/fc-install-host" "$repo_copy/bin/fc-install-host"
  cp "$REPO_ROOT/lib/common.sh" "$REPO_ROOT/lib/config.sh" "$repo_copy/lib/"
  perl -0pi -e 's/\nmain "\$@"\s*\z/\n/' "$repo_copy/bin/fc-install-host"

  cat > "$stub_dir/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"tag_name":"v1.9.0"}\n'
EOF
  chmod +x "$stub_dir/curl"

  cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
printf 'v1.9.0\n'
EOF
  chmod +x "$stub_dir/jq"

  resolved_version=$(PATH="$stub_dir:$PATH" bash -c 'source "$1"; fc_resolve_firecracker_version' _ "$repo_copy/bin/fc-install-host") || return 1

  [[ "$resolved_version" == 'v1.9.0' ]] || fail "latest version resolution emitted unexpected output: $resolved_version"
)

test_host_install_provisions_firecracker_binaries_and_kernel() (
  local tmpdir stub_dir binary_root runtime_root log_root
  local curl_log install_log apt_log

  tmpdir=$(mktemp -d)
  stub_dir="$tmpdir/stubs"
  binary_root="$tmpdir/binroot"
  runtime_root="$tmpdir/runtime"
  log_root="$tmpdir/logs"
  curl_log="$tmpdir/curl.log"
  install_log="$tmpdir/install.log"
  apt_log="$tmpdir/apt.log"

  mkdir -p "$stub_dir"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@host\n' > "$stub_dir/authorized_keys"

  cat > "$stub_dir/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then
  if [[ "${2:-}" == 'firecracker' ]]; then printf '999\n'; else printf '0\n'; fi
elif [[ "${1:-}" == '-g' && "${2:-}" == 'firecracker' ]]; then
  printf '997\n'
elif [[ "${1:-}" == 'firecracker' ]]; then
  printf 'uid=999(firecracker) gid=997(firecracker) groups=997(firecracker)\n'
else
  /usr/bin/id "$@"
fi
EOF
  chmod +x "$stub_dir/id"

  cat > "$stub_dir/useradd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/useradd"

  cat > "$stub_dir/dpkg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-s' ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$stub_dir/dpkg"

  cat > "$stub_dir/apt-get" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$apt_log"
exit 0
EOF
  chmod +x "$stub_dir/apt-get"

  cat > "$stub_dir/install" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$install_log"
/usr/bin/install "\$@"
EOF
  chmod +x "$stub_dir/install"

  cat > "$stub_dir/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$curl_log"
output_path=
url=
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o|--output)
      output_path=\$2
      shift 2
      ;;
    *)
      url=\$1
      shift
      ;;
  esac
done
  if [[ "\$url" == *"s3.amazonaws.com/spec.ccfc.min/?prefix="* ]]; then
    printf '<ListBucketResult><Contents><Key>firecracker-ci/v1.9/x86_64/vmlinux-6.1.111</Key></Contents></ListBucketResult>\n'
    exit 0
  fi
[[ -n "\$output_path" ]] || exit 1
: > "\$output_path"
EOF
  chmod +x "$stub_dir/curl"

  cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
printf 'v1.9.0\n'
EOF
  chmod +x "$stub_dir/jq"

  cat > "$stub_dir/sha256sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/sha256sum"

  cat > "$stub_dir/tar" <<'EOF'
#!/usr/bin/env bash
archive=
target_dir=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C)
      target_dir=$2
      shift 2
      ;;
    *.tgz)
      archive=$1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
base=$(basename "$archive" .tgz)
version=${base#firecracker-}
arch=${version##*-}
version=${version%-${arch}}
release_dir="$target_dir/release-${version}-${arch}"
mkdir -p "$release_dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$release_dir/firecracker-${version}-${arch}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$release_dir/jailer-${version}-${arch}"
chmod +x "$release_dir/firecracker-${version}-${arch}" "$release_dir/jailer-${version}-${arch}"
EOF
  chmod +x "$stub_dir/tar"

  PATH="$stub_dir:$PATH" \
    FC_BINARY_ROOT="$binary_root" \
    FC_RUNTIME_ROOT="$runtime_root" \
    FC_LOG_ROOT="$log_root" \
    FC_FIRECRACKER_VERSION="v1.9.0" \
    bash "$REPO_ROOT/bin/fc-install-host" --ssh-key-file "$stub_dir/authorized_keys" || return 1

  [[ -x "$binary_root/firecracker" ]] || fail "host install did not provision firecracker binary"
  [[ -x "$binary_root/jailer" ]] || fail "host install did not provision jailer binary"
  [[ -f "$binary_root/vmlinux.bin" ]] || fail "host install did not provision default guest kernel"
  [[ -f "$runtime_root/host.env" ]] || fail "host install did not write host.env"
  grep -q '^FC_GUEST_USER=' "$runtime_root/host.env" || fail "host.env missing FC_GUEST_USER"
  grep -q '^FC_SSH_KEY_FILE=' "$runtime_root/host.env" || fail "host.env missing FC_SSH_KEY_FILE"
  grep -q '^FC_JAILER_UID=999$' "$runtime_root/host.env" || fail "host.env missing FC_JAILER_UID=999"
  grep -q '^FC_JAILER_GID=997$' "$runtime_root/host.env" || fail "host.env missing FC_JAILER_GID=997"
)

test_host_install_avoids_qemu_package_replacement_when_qemu_img_exists() (
  local tmpdir stub_dir binary_root runtime_root log_root
  local curl_log install_log apt_log

  tmpdir=$(mktemp -d)
  stub_dir="$tmpdir/stubs"
  binary_root="$tmpdir/binroot"
  runtime_root="$tmpdir/runtime"
  log_root="$tmpdir/logs"
  curl_log="$tmpdir/curl.log"
  install_log="$tmpdir/install.log"
  apt_log="$tmpdir/apt.log"

  mkdir -p "$stub_dir"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@host\n' > "$stub_dir/authorized_keys"

  cat > "$stub_dir/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '-u' ]]; then
  if [[ "${2:-}" == 'firecracker' ]]; then printf '999\n'; else printf '0\n'; fi
elif [[ "${1:-}" == '-g' && "${2:-}" == 'firecracker' ]]; then
  printf '997\n'
elif [[ "${1:-}" == 'firecracker' ]]; then
  printf 'uid=999(firecracker) gid=997(firecracker) groups=997(firecracker)\n'
else
  /usr/bin/id "$@"
fi
EOF
  chmod +x "$stub_dir/id"

  cat > "$stub_dir/useradd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/useradd"

  cat > "$stub_dir/dpkg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != '-s' ]]; then
  exit 1
fi
case "$2" in
  curl|e2fsprogs)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$stub_dir/dpkg"

  cat > "$stub_dir/apt-get" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$apt_log"
exit 0
EOF
  chmod +x "$stub_dir/apt-get"

  cat > "$stub_dir/install" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$install_log"
/usr/bin/install "\$@"
EOF
  chmod +x "$stub_dir/install"

  cat > "$stub_dir/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$curl_log"
output_path=
url=
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o|--output)
      output_path=\$2
      shift 2
      ;;
    *)
      url=\$1
      shift
      ;;
  esac
done
  if [[ "\$url" == *"s3.amazonaws.com/spec.ccfc.min/?prefix="* ]]; then
    printf '<ListBucketResult><Contents><Key>firecracker-ci/v1.9/x86_64/vmlinux-6.1.111</Key></Contents></ListBucketResult>\n'
    exit 0
  fi
[[ -n "\$output_path" ]] || exit 1
: > "\$output_path"
EOF
  chmod +x "$stub_dir/curl"

  cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
printf 'v1.9.0\n'
EOF
  chmod +x "$stub_dir/jq"

  cat > "$stub_dir/qemu-img" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/qemu-img"

  cat > "$stub_dir/sha256sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/sha256sum"

  cat > "$stub_dir/tar" <<'EOF'
#!/usr/bin/env bash
archive=
target_dir=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C)
      target_dir=$2
      shift 2
      ;;
    *.tgz)
      archive=$1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
base=$(basename "$archive" .tgz)
version=${base#firecracker-}
arch=${version##*-}
version=${version%-${arch}}
release_dir="$target_dir/release-${version}-${arch}"
mkdir -p "$release_dir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$release_dir/firecracker-${version}-${arch}"
printf '#!/usr/bin/env bash\nexit 0\n' > "$release_dir/jailer-${version}-${arch}"
chmod +x "$release_dir/firecracker-${version}-${arch}" "$release_dir/jailer-${version}-${arch}"
EOF
  chmod +x "$stub_dir/tar"

  PATH="$stub_dir:$PATH" \
    FC_BINARY_ROOT="$binary_root" \
    FC_RUNTIME_ROOT="$runtime_root" \
    FC_LOG_ROOT="$log_root" \
    FC_FIRECRACKER_VERSION="v1.9.0" \
    bash "$REPO_ROOT/bin/fc-install-host" --ssh-key-file "$stub_dir/authorized_keys" || return 1

  grep -q '^install -y --no-install-recommends jq$' "$apt_log" || fail "host install did not limit package install to required safe packages"
  if grep -q 'qemu-utils|cloud-image-utils|libguestfs-tools' "$apt_log"; then
    fail "host install attempted conflicting or optional packages despite existing runtime commands"
  fi
)

main() {
  test_resolve_latest_version_emits_clean_tag_only || return 1
  test_host_install_provisions_firecracker_binaries_and_kernel || return 1
  test_host_install_avoids_qemu_package_replacement_when_qemu_img_exists || return 1
  printf 'PASS: host install checks\n'
}

main "$@"
