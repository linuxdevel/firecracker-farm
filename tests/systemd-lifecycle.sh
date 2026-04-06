#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

create_stub() {
  local stub_dir=$1
  local name=$2
  local body=$3

  mkdir -p "$stub_dir"
  cat > "$stub_dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$stub_dir/$name"
}

test_fc_start_installs_stable_control_files_and_renders_simple_unit() (
  local tmpdir unit_dir runtime_root log_root log_path unit_path control_root

  tmpdir=$(mktemp -d)
  unit_dir="$tmpdir/systemd"
  runtime_root="$tmpdir/runtime"
  log_root="$tmpdir/logs"
  log_path="$tmpdir/systemctl.log"
  unit_path="$unit_dir/firecracker@.service"
  control_root="$runtime_root/control"

  create_stub "$tmpdir/bin" systemctl "printf '%s\\n' \"\$*\" >> '$log_path'"
  create_stub "$tmpdir/bin" sudo 'if [[ "${1:-}" == "-n" ]]; then shift; fi; exec "$@"'
  create_stub "$tmpdir/bin" id 'if [[ "${1:-}" == "-u" ]]; then printf "0\n"; else /usr/bin/id "$@"; fi'

  PATH="$tmpdir/bin:$PATH" \
    FC_RUNTIME_ROOT="$runtime_root" \
    FC_LOG_ROOT="$log_root" \
    FC_SYSTEMD_SYSTEM_DIR="$unit_dir" \
    bash "$REPO_ROOT/bin/fc-start" testvm || return 1

  [[ -f "$unit_path" ]] || fail "fc-start did not install the systemd template unit"
  [[ -x "$control_root/bin/fc-start" ]] || fail "fc-start did not sync a stable control copy"
  [[ -x "$control_root/bin/fc-stop" ]] || fail "fc-start did not sync fc-stop into the stable control path"
  [[ -f "$control_root/lib/firecracker.sh" ]] || fail "fc-start did not sync runtime libraries into the stable control path"
  [[ -f "$control_root/templates/vm-config.json.tmpl" ]] || fail "fc-start did not sync templates into the stable control path"
  grep -q '^Description=Firecracker microVM %i$' "$unit_path" || fail "installed unit missing template description"
  grep -q '^Type=simple$' "$unit_path" || fail "installed unit missing Type=simple"
  grep -q '^KillMode=control-group$' "$unit_path" || fail "installed unit missing KillMode=control-group"
  grep -q "^WorkingDirectory=${control_root}$" "$unit_path" || fail "installed unit missing stable working directory"
  grep -q "^ExecStart=${control_root}/bin/fc-start --direct %i$" "$unit_path" || fail "installed unit missing stable direct ExecStart"
  grep -q "^ExecStopPost=${control_root}/bin/fc-stop --direct %i$" "$unit_path" || fail "installed unit missing ExecStopPost cleanup"
  if grep -q "$REPO_ROOT" "$unit_path"; then
    fail "installed unit still hardcodes the transient worktree path"
  fi
  [[ "$(sed -n '1p' "$log_path")" == 'daemon-reload' ]] || fail "fc-start did not reload systemd units after install"
  [[ "$(sed -n '2p' "$log_path")" == 'enable --now firecracker@testvm.service' ]] || fail "fc-start did not enable and start the expected instance unit"
)

test_fc_start_reexecs_with_sudo_for_operator_flow() (
  local tmpdir unit_dir runtime_root log_root systemctl_log sudo_log

  tmpdir=$(mktemp -d)
  unit_dir="$tmpdir/systemd"
  runtime_root="$tmpdir/runtime"
  log_root="$tmpdir/logs"
  systemctl_log="$tmpdir/systemctl.log"
  sudo_log="$tmpdir/sudo.log"

  create_stub "$tmpdir/bin" systemctl "printf '%s\\n' \"\$*\" >> '$systemctl_log'"
  create_stub "$tmpdir/bin" sudo "printf '%s\\n' \"\$*\" >> '$sudo_log'; if [[ \"\${1:-}\" == '-n' ]]; then shift; fi; export FC_TEST_SUDO_ACTIVE=1; exec \"\$@\""
  create_stub "$tmpdir/bin" id 'if [[ "${1:-}" == "-u" ]]; then if [[ -n "${FC_TEST_SUDO_ACTIVE:-}" ]]; then printf "0\n"; else printf "1000\n"; fi; else /usr/bin/id "$@"; fi'

  PATH="$tmpdir/bin:$PATH" \
    FC_RUNTIME_ROOT="$runtime_root" \
    FC_LOG_ROOT="$log_root" \
    FC_SYSTEMD_SYSTEM_DIR="$unit_dir" \
    bash "$REPO_ROOT/bin/fc-start" testvm || return 1

  [[ "$(sed -n '1p' "$sudo_log")" == "-n $REPO_ROOT/bin/fc-start testvm" ]] || fail "fc-start did not re-exec through passwordless sudo for operator flow"
  [[ "$(sed -n '2p' "$systemctl_log")" == 'enable --now firecracker@testvm.service' ]] || fail "fc-start did not complete the systemd start after sudo re-exec"
)

test_fc_stop_reexecs_with_sudo_and_stops_instance_unit() (
  local tmpdir systemctl_log sudo_log

  tmpdir=$(mktemp -d)
  systemctl_log="$tmpdir/systemctl.log"
  sudo_log="$tmpdir/sudo.log"

  create_stub "$tmpdir/bin" systemctl "printf '%s\\n' \"\$*\" >> '$systemctl_log'"
  create_stub "$tmpdir/bin" sudo "printf '%s\\n' \"\$*\" >> '$sudo_log'; if [[ \"\${1:-}\" == '-n' ]]; then shift; fi; export FC_TEST_SUDO_ACTIVE=1; exec \"\$@\""
  create_stub "$tmpdir/bin" id 'if [[ "${1:-}" == "-u" ]]; then if [[ -n "${FC_TEST_SUDO_ACTIVE:-}" ]]; then printf "0\n"; else printf "1000\n"; fi; else /usr/bin/id "$@"; fi'

  PATH="$tmpdir/bin:$PATH" bash "$REPO_ROOT/bin/fc-stop" testvm || return 1

  [[ "$(sed -n '1p' "$sudo_log")" == "-n $REPO_ROOT/bin/fc-stop testvm" ]] || fail "fc-stop did not re-exec through passwordless sudo for operator flow"
  [[ "$(sed -n '1p' "$systemctl_log")" == 'disable --now firecracker@testvm.service' ]] || fail "fc-stop did not disable and stop the expected instance unit"
)

main() {
  test_fc_start_installs_stable_control_files_and_renders_simple_unit || return 1
  test_fc_start_reexecs_with_sudo_for_operator_flow || return 1
  test_fc_stop_reexecs_with_sudo_and_stops_instance_unit || return 1
  printf 'PASS: systemd lifecycle checks\n'
}

main "$@"
