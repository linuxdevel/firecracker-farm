#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

test_fc_ssh_resolves_ip_and_constructs_ssh_command() (
    local tmpdir ssh_log
    tmpdir=$(mktemp -d)
    ssh_log="$tmpdir/ssh.log"

    # Create mock ssh that logs its arguments
    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FC_TEST_SSH_LOG}"
MOCK
    chmod +x "$tmpdir/bin/ssh"

    # Create mock metadata
    mkdir -p "$tmpdir/runtime/vms/testvm"
    cat > "$tmpdir/runtime/vms/testvm/vm.env" <<EOF
VM_NAME=testvm
MAC_ADDRESS=02:18:8c:c0:a7:f8
BRIDGE_NAME=vmbr0
TAP_NAME=fc-testvm0
EOF

    # Create mock ip command for neighbor lookup
    cat > "$tmpdir/bin/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "neigh" && "$2" == "show" ]]; then
    printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
fi
MOCK
    chmod +x "$tmpdir/bin/ip"

    FC_TEST_SSH_LOG="$ssh_log" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    FC_GUEST_USER="testuser" \
    PATH="$tmpdir/bin:$PATH" \
        bash "$REPO_ROOT/bin/fc-ssh" testvm || fail "fc-ssh failed"

    [[ -f "$ssh_log" ]] || fail "ssh was not invoked"
    grep -q 'StrictHostKeyChecking=no' "$ssh_log" || fail "ssh missing StrictHostKeyChecking=no"
    grep -q 'UserKnownHostsFile=/dev/null' "$ssh_log" || fail "ssh missing UserKnownHostsFile"
    grep -q 'testuser@192.168.1.107' "$ssh_log" || fail "ssh missing user@ip"
)

test_fc_ssh_passes_extra_args_after_separator() (
    local tmpdir ssh_log
    tmpdir=$(mktemp -d)
    ssh_log="$tmpdir/ssh.log"

    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FC_TEST_SSH_LOG}"
MOCK
    chmod +x "$tmpdir/bin/ssh"

    mkdir -p "$tmpdir/runtime/vms/testvm"
    cat > "$tmpdir/runtime/vms/testvm/vm.env" <<EOF
VM_NAME=testvm
MAC_ADDRESS=02:18:8c:c0:a7:f8
BRIDGE_NAME=vmbr0
TAP_NAME=fc-testvm0
EOF

    cat > "$tmpdir/bin/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "neigh" && "$2" == "show" ]]; then
    printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
fi
MOCK
    chmod +x "$tmpdir/bin/ip"

    FC_TEST_SSH_LOG="$ssh_log" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    FC_GUEST_USER="testuser" \
    PATH="$tmpdir/bin:$PATH" \
        bash "$REPO_ROOT/bin/fc-ssh" testvm -- -L 8080:localhost:80 || fail "fc-ssh with extra args failed"

    [[ -f "$ssh_log" ]] || fail "ssh was not invoked"
    grep -q '\-L 8080:localhost:80' "$ssh_log" || fail "ssh missing port forward arg"
)

test_fc_ssh_uses_identity_flag() (
    local tmpdir ssh_log
    tmpdir=$(mktemp -d)
    ssh_log="$tmpdir/ssh.log"

    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FC_TEST_SSH_LOG}"
MOCK
    chmod +x "$tmpdir/bin/ssh"

    mkdir -p "$tmpdir/runtime/vms/testvm"
    cat > "$tmpdir/runtime/vms/testvm/vm.env" <<EOF
VM_NAME=testvm
MAC_ADDRESS=02:18:8c:c0:a7:f8
BRIDGE_NAME=vmbr0
TAP_NAME=fc-testvm0
EOF

    cat > "$tmpdir/bin/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "neigh" && "$2" == "show" ]]; then
    printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
fi
MOCK
    chmod +x "$tmpdir/bin/ip"

    FC_TEST_SSH_LOG="$ssh_log" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    FC_GUEST_USER="testuser" \
    PATH="$tmpdir/bin:$PATH" \
        bash "$REPO_ROOT/bin/fc-ssh" --identity /path/to/key testvm || fail "fc-ssh with identity failed"

    [[ -f "$ssh_log" ]] || fail "ssh was not invoked"
    grep -q '\-i /path/to/key' "$ssh_log" || fail "ssh missing -i /path/to/key"
)

test_fc_ssh_copy_id_mode() (
    local tmpdir copy_id_log
    tmpdir=$(mktemp -d)
    copy_id_log="$tmpdir/copy-id.log"

    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/ssh-copy-id" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FC_TEST_COPY_ID_LOG}"
MOCK
    chmod +x "$tmpdir/bin/ssh-copy-id"

    # Also need a mock ssh (not called, but PATH needs it)
    cat > "$tmpdir/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$tmpdir/bin/ssh"

    mkdir -p "$tmpdir/runtime/vms/testvm"
    cat > "$tmpdir/runtime/vms/testvm/vm.env" <<EOF
VM_NAME=testvm
MAC_ADDRESS=02:18:8c:c0:a7:f8
BRIDGE_NAME=vmbr0
TAP_NAME=fc-testvm0
EOF

    cat > "$tmpdir/bin/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "neigh" && "$2" == "show" ]]; then
    printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
fi
MOCK
    chmod +x "$tmpdir/bin/ip"

    FC_TEST_COPY_ID_LOG="$copy_id_log" \
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    FC_GUEST_USER="testuser" \
    PATH="$tmpdir/bin:$PATH" \
        bash "$REPO_ROOT/bin/fc-ssh" testvm --copy-id || fail "fc-ssh --copy-id failed"

    [[ -f "$copy_id_log" ]] || fail "ssh-copy-id was not invoked"
    grep -q 'testuser@192.168.1.107' "$copy_id_log" || fail "ssh-copy-id missing user@ip"
)

test_fc_ssh_fails_when_ip_cannot_be_resolved() (
    local tmpdir output_file status
    tmpdir=$(mktemp -d)
    output_file="$tmpdir/output"

    mkdir -p "$tmpdir/bin"

    mkdir -p "$tmpdir/runtime/vms/testvm"
    cat > "$tmpdir/runtime/vms/testvm/vm.env" <<EOF
VM_NAME=testvm
MAC_ADDRESS=02:ff:ff:ff:ff:ff
BRIDGE_NAME=vmbr0
TAP_NAME=fc-testvm0
EOF

    # ip neigh returns nothing matching this MAC
    cat > "$tmpdir/bin/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "neigh" && "$2" == "show" ]]; then
    printf '192.168.1.107 dev vmbr0 lladdr 02:18:8c:c0:a7:f8 REACHABLE\n'
fi
MOCK
    chmod +x "$tmpdir/bin/ip"

    # Mock arping to prevent real arping from running
    cat > "$tmpdir/bin/arping" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$tmpdir/bin/arping"

    set +e
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
    FC_GUEST_USER="testuser" \
    PATH="$tmpdir/bin:$PATH" \
        bash "$REPO_ROOT/bin/fc-ssh" testvm > "$output_file" 2>&1
    status=$?
    set -e

    [[ "$status" -ne 0 ]] || fail "fc-ssh should fail when IP cannot be resolved"
    grep -q 'could not resolve IP' "$output_file" || fail "fc-ssh missing IP resolution error message"
)

test_fc_ssh_fails_when_no_vm_name_given() (
    local tmpdir output_file status
    tmpdir=$(mktemp -d)
    output_file="$tmpdir/output"

    set +e
    FC_RUNTIME_ROOT="$tmpdir/runtime" \
        bash "$REPO_ROOT/bin/fc-ssh" > "$output_file" 2>&1
    status=$?
    set -e

    [[ "$status" -ne 0 ]] || fail "fc-ssh should fail when no VM name given"
    grep -q 'Usage:' "$output_file" || fail "fc-ssh missing usage message when no VM name given"
)

main() {
    test_fc_ssh_resolves_ip_and_constructs_ssh_command || return 1
    test_fc_ssh_passes_extra_args_after_separator || return 1
    test_fc_ssh_uses_identity_flag || return 1
    test_fc_ssh_copy_id_mode || return 1
    test_fc_ssh_fails_when_ip_cannot_be_resolved || return 1
    test_fc_ssh_fails_when_no_vm_name_given || return 1
    printf 'PASS: ssh command checks\n'
}

main "$@"
