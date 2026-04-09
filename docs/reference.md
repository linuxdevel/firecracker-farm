# firecracker-farm reference

Unless noted otherwise, examples here describe the current host configuration
(for example `vmbr0`) rather than a product requirement for a specific platform.

## Commands

### install.sh

One-line installer for firecracker-farm. Downloads a release tarball from
GitHub, extracts it to `/opt/firecracker-farm/`, creates `fc-*` symlinks in
`/usr/local/bin/`, and runs `fc-install-host` to provision the Firecracker
runtime.

```
curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh | sudo bash
curl -fsSL ... | sudo bash -s -- [OPTIONS]
```

| Flag | Description |
|------|-------------|
| `--version TAG` | Install a specific release (default: latest) |
| `--guest-user USER` | Username for VM guests (passed to `fc-install-host`) |
| `--ssh-key-file PATH` | SSH public key file (passed to `fc-install-host`) |
| `-h`, `--help` | Show usage |

Steps:
1. Require root
2. Ensure `curl`, `tar`, and `jq` are available (installs `jq` if missing)
3. Resolve the latest release tag from GitHub API (unless `--version` is given)
4. Download `firecracker-farm-<version>.tar.gz` from the GitHub release
5. Extract to `/opt/firecracker-farm/` (replaces any existing install)
6. Create symlinks for all `fc-*` commands in `/usr/local/bin/`
7. Run `fc-install-host` with any `--guest-user` / `--ssh-key-file` flags

Examples:

```bash
# Install latest, auto-detect user
curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh | sudo bash

# Explicit user and key
curl -fsSL ... | sudo bash -s -- --guest-user myuser --ssh-key-file /home/myuser/.ssh/authorized_keys

# Pin a specific version
curl -fsSL ... | sudo bash -s -- --version v1.0.0
```

---

### fc-install-host

Install host prerequisites, Firecracker binaries, and the guest kernel.

```
fc-install-host [--preflight|--install|-h|--help]
```

| Flag | Description |
|------|-------------|
| *(none)* | Run the full install |
| `--preflight` | Read-only host readiness check only |
| `--install` | Explicit alias for the full install |
| `--guest-user USER` | Username for the VM guest (default: operator username) |
| `--ssh-key-file PATH` | SSH public key file to embed (default: `~/.ssh/authorized_keys`) |
| `-h`, `--help` | Show usage |

Installs required packages (`curl`, `jq`, `qemu-utils`, `e2fsprogs`), creates
dedicated directories, downloads the latest Firecracker release binaries
(`firecracker`, `jailer`), and downloads the matching CI guest kernel.

Environment:

| Variable | Effect |
|----------|--------|
| `FC_FIRECRACKER_VERSION` | Pin a specific release tag (default: `latest`) |
| `FC_KERNEL_IMAGE_URL` | Override the guest kernel download URL |

---

### fc_image_build_template

Build the reusable Ubuntu rootfs template. This is a library function, not a
standalone command.

```
sudo bash -c 'source lib/image.sh && fc_image_build_template [OPTIONS]'
```

| Flag | Description |
|------|-------------|
| `--ssh-key-file PATH` | SSH public key file to embed (default: from host config) |
| `--offline-customize` | Require `virt-customize` to inject metadata |
| `--skip-customize` | Skip offline customization entirely |
| `-h`, `--help` | Show usage |

Pipeline steps:
1. Download Ubuntu cloud image (qcow2)
2. Convert to raw
3. Extract root partition (partition 1) into standalone ext4 filesystem
4. Patch `/etc/fstab` (comment out BOOT, UEFI, cloudimg-rootfs entries)
5. Render cloud-init user-data and meta-data templates
6. Optional offline customization via `virt-customize`
7. Publish all outputs atomically

Output files under `/var/lib/firecracker/images/`:

| File | Purpose |
|------|---------|
| `ubuntu-template.img` | Original downloaded cloud image |
| `ubuntu-template.raw` | Extracted bare ext4 rootfs template |
| `ubuntu-template-user-data.yaml` | Rendered user-data |
| `ubuntu-template-meta-data.yaml` | Rendered meta-data |
| `ubuntu-template.metadata` | Build metadata |

---

### fc-create

Create a persistent VM instance (disk + metadata + cloud-init seed).

```
fc-create <name> [--disk-size SIZE] [--vcpus N] [--memory SIZE]
```

| Flag | Description |
|------|-------------|
| `--disk-size SIZE` | Disk size (e.g. `20G`, `512M`). Prompted interactively if omitted. |
| `--vcpus N` | Number of vCPUs (default: 1). Must be >= 1. |
| `--memory SIZE` | Memory size (e.g. `2048m`, `2g`). Normalized to MiB. Default: 1024 MiB. Must be >= 128 MiB. |
| `-h`, `--help` | Show usage |

Steps:
1. Validate VM name (lowercase alphanumeric + hyphens, must start with letter)
2. Validate derived tap name fits Linux 15-char interface name limit
3. Clone template to per-instance disk
4. Resize disk with `qemu-img resize` + `resize2fs`
5. Loop-mount disk and inject cloud-init seed into `/var/lib/cloud/seed/nocloud/`
6. Write instance metadata (`vm.env`) and network identity

Re-execs through `sudo` when invoked by a non-root user.

---

### fc-start

Start a Firecracker VM instance.

```
fc-start [--direct] <name>
```

| Flag | Description |
|------|-------------|
| `--direct` | Launch via jailer directly, without systemd (used by ExecStart) |
| `-h`, `--help` | Show usage |

Default mode (without `--direct`):
1. Sync control scripts to `/var/lib/firecracker/control/`
2. Render and install systemd template unit `firecracker@.service`
3. `systemctl enable --now firecracker@<name>.service`

Direct mode (`--direct`):
1. Create tap device and attach to bridge
2. Render Firecracker JSON config from instance metadata
3. Hard-link persistent rootfs into jailer chroot
4. Launch Firecracker via jailer with `--daemonize`
5. Start bounded log capture (stdout/stderr, max 1 MiB each)
6. Record PID and write runtime state

Re-execs through `sudo` when invoked by a non-root user.

---

### fc-stop

Stop a running Firecracker VM instance.

```
fc-stop [--direct] [--force] <name>
```

| Flag | Description |
|------|-------------|
| `--direct` | Stop the Firecracker process directly (used by ExecStop) |
| `--force` | Skip SIGTERM, send SIGKILL immediately + cgroup cleanup |
| `-h`, `--help` | Show usage |

Default mode: `systemctl disable --now firecracker@<name>.service`

Direct mode: SIGTERM the Firecracker process, wait up to 5 seconds. If the
process doesn't exit, escalate to SIGKILL with a 2-second timeout. After
the main process is dead, clean up any orphaned processes in the jailer
cgroup, delete the tap device, and clean up log capture and PID files.

Force mode (`--force`): skip SIGTERM entirely and send SIGKILL immediately,
then perform cgroup cleanup.

Idempotent: calling `fc-stop` on an already-stopped VM cleans up any stale
resources (tap device, log pipes, PID files) without erroring.

Re-execs through `sudo` when invoked by a non-root user.

---

### fc-status

Show detailed VM status.

```
fc-status <name>
```

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show usage |

Output (vertical key-value format):

```
Name:      myvm
Status:    running
PID:       12345
vCPUs:     2
Memory:    2048 MiB
Disk:      20G
IP:        192.168.1.107
TAP:       fc-myvm0
Bridge:    vmbr0
Uptime:    2d 4h 12m
```

IP address is resolved from the host ARP/neighbor table using the VM's
known MAC address. Shows `-` if the VM is stopped or the IP cannot be resolved.

Uptime is derived from the Firecracker process start time.

---

### fc-list

List all VM instances with their status in a formatted table.

```
fc-list
```

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show usage |

Output:

```
NAME         STATUS   PID     VCPUS  MEMORY   DISK   IP              TAP              BRIDGE   UPTIME
myvm         running  12345   2      2048M    20G    192.168.1.107   fc-myvm0         vmbr0    2d 4h 12m
testbox      stopped  -       1      1024M    10G    -               fc-testbox0      vmbr0    -
```

Scans `/var/lib/firecracker/vms/` for directories containing `vm.env`.
IP addresses are resolved from the host ARP/neighbor table.

---

### fc-ssh

Open an SSH session to a running Firecracker VM.

```
fc-ssh [options] <name> [-- ssh-args...]
```

| Flag | Description |
|------|-------------|
| `--identity PATH` | Use a specific private key file |
| `--copy-id` | Copy SSH public key to the guest (uses `ssh-copy-id`) |
| `-h`, `--help` | Show usage |

Resolves the VM's IP from its MAC address in the host ARP/neighbor table,
then opens an SSH connection as the configured guest user.

Does NOT require root.

Examples:

```bash
fc-ssh myvm                          # interactive shell
fc-ssh myvm -- ls -la /tmp           # run a remote command
fc-ssh myvm -- -L 8080:localhost:80  # SSH port forward
fc-ssh myvm --copy-id                # install SSH key on guest
fc-ssh myvm --identity ~/.ssh/id_rsa # use a specific key
```

SSH options applied automatically:
- `StrictHostKeyChecking=no` (VMs get new host keys on each create)
- `UserKnownHostsFile=/dev/null` (IPs are reused via DHCP)

---

## Environment variables

All variables have defaults in `lib/config.sh` and can be overridden via
environment.

| Variable | Default | Description |
|----------|---------|-------------|
| `FC_HOST_IP` | `192.168.1.2` | Host IP address |
| `FC_DEFAULT_BRIDGE` | `vmbr0` | Linux bridge for VM tap devices |
| `FC_DEFAULT_DISK_SIZE` | `20G` | Default disk size when prompted |
| `FC_DEFAULT_MEMORY_MIB` | `1024` | RAM in MiB (used in Firecracker config) |
| `FC_DEFAULT_VCPUS` | `1` | Number of vCPUs |
| `FC_RUNTIME_ROOT` | `/var/lib/firecracker` | Root for images, VMs, and runtime state |
| `FC_LOG_ROOT` | `/var/log/firecracker` | Root for VM log files |
| `FC_BINARY_ROOT` | `/opt/firecracker/bin` | Firecracker and jailer binaries |
| `FC_PREFLIGHT_MIN_FREE_MIB` | `20480` | Minimum free space required for preflight (MiB) |
| `FC_GUEST_USER` | operator username | Username for VM guest |
| `FC_SSH_KEY_FILE` | `~/.ssh/authorized_keys` | SSH public key file to embed |
| `FC_FIRECRACKER_VERSION` | `latest` | Firecracker release tag to install |
| `FC_KERNEL_IMAGE_URL` | *(auto-resolved)* | Override guest kernel download URL |
| `FC_UBUNTU_RELEASE` | `noble` | Ubuntu release codename for cloud image |
| `FC_UBUNTU_CLOUD_IMAGE_URL` | *(derived from release)* | Override cloud image download URL |
| `FC_SYSTEMD_SYSTEM_DIR` | `/etc/systemd/system` | systemd unit install directory |

---

## File layout on the host

### Binaries

```
/opt/firecracker/bin/
  firecracker        Firecracker VMM binary
  jailer             Jailer binary
  vmlinux.bin        Guest kernel
```

### Host configuration

```
/var/lib/firecracker/
  host.env               Operator identity (guest user, SSH key path)
```

### Template images

```
/var/lib/firecracker/images/
  ubuntu-template.img              Downloaded cloud image (qcow2)
  ubuntu-template.raw              Bare ext4 rootfs template
  ubuntu-template-user-data.yaml   Rendered cloud-init user-data
  ubuntu-template-meta-data.yaml   Rendered cloud-init meta-data
  ubuntu-template.metadata         Build metadata
```

### Per-instance files

```
/var/lib/firecracker/vms/<name>/
  rootfs.raw         Persistent writable rootfs disk
  vm.env             Instance metadata (name, disk, vCPUs, memory, rootfs, tap, MAC, bridge)
  user-data          Cloud-init user-data copy
  meta-data          Cloud-init meta-data copy
  runtime/           Created at start, holds runtime state
    firecracker.pid  Firecracker process PID
    state.env        Runtime state (status, PID, API socket)
    stdout.pipe      Named pipe for stdout log capture
    stderr.pipe      Named pipe for stderr log capture
    jailer/firecracker/<name>/root/
      config.json    Rendered Firecracker VM config
      rootfs.raw     Hard link to persistent rootfs
      vmlinux.bin    Copy of guest kernel
      api.socket     Firecracker API socket
```

### Control scripts (synced at start)

```
/var/lib/firecracker/control/
  bin/fc-start       Stable copy of start script
  bin/fc-stop        Stable copy of stop script
  lib/               Stable copies of shell libraries
  templates/         Stable copy of VM config template
```

### Logs

```
/var/log/firecracker/
  <name>.stdout.log  Firecracker stdout (bounded to 1 MiB)
  <name>.stderr.log  Firecracker stderr (bounded to 1 MiB)
```

### systemd

```
/etc/systemd/system/
  firecracker@.service   Template unit (installed by fc-start)
```

Unit properties:
- `Type=forking` with `PIDFile` pointing to `runtime/firecracker.pid`
- `ExecStart` calls `fc-start --direct %i`
- `ExecStop` calls `fc-stop --direct %i`
- `KillMode=none` (stop is handled by the ExecStop script)
- `WantedBy=multi-user.target`

---

## Instance metadata format (vm.env)

```
VM_NAME=myvm
INSTANCE_DIR=/var/lib/firecracker/vms/myvm
DISK_SIZE=20G
ROOTFS_FILENAME=rootfs.raw
ROOTFS_PATH=/var/lib/firecracker/vms/myvm/rootfs.raw
TEMPLATE_PATH=/var/lib/firecracker/images/ubuntu-template.raw
CREATED_AT_UTC=2026-04-05T12:00:00Z
TAP_NAME=fc-myvm0
MAC_ADDRESS=02:xx:xx:xx:xx:xx
BRIDGE_NAME=vmbr0
VCPU_COUNT=2
MEM_SIZE_MIB=2048
```

`VCPU_COUNT` and `MEM_SIZE_MIB` are written by `fc-create` when `--vcpus`
or `--memory` flags are provided. When omitted, they are written with
default values from `FC_DEFAULT_VCPUS` (1) and `FC_DEFAULT_MEMORY_MIB` (1024).

Optional overrides (per-instance, manual edit):
- `KERNEL_IMAGE_PATH` — custom kernel path

---

## Networking

- Each VM gets a tap device named `fc-<name>0`
- MAC address is deterministic: `02:` prefix + first 10 hex chars of `sha256(name)`
- Tap is attached to the configured bridge (`vmbr0` by default)
- Guest gets IPv4 via DHCP (cloud-init configures netplan with matching MAC)
- The host-side tap does NOT have the guest MAC set (this was a critical DHCP
  bug fix — setting the same MAC on the tap caused the bridge to misroute
  DHCP replies)

---

## Templates

### vm-config.json.tmpl

Firecracker static JSON config. Placeholders:

| Placeholder | Source |
|-------------|--------|
| `{{KERNEL_IMAGE_PATH}}` | Kernel filename in jail root |
| `{{ROOTFS_PATH}}` | Rootfs filename in jail root |
| `{{TAP_NAME}}` | Tap device name from vm.env |
| `{{MAC_ADDRESS}}` | Guest MAC from vm.env |
| `{{VCPU_COUNT}}` | From vm.env or default |
| `{{MEM_SIZE_MIB}}` | From vm.env or default |

### cloud-init-user-data.yaml

| Placeholder | Source |
|-------------|--------|
| `__FC_SSH_AUTHORIZED_KEY__` | First line from SSH key file |
| `__FC_GUEST_USER__` | Guest username from config |

Creates the configured guest user with passwordless sudo and SSH key access.

### cloud-init-meta-data.yaml

| Placeholder | Source |
|-------------|--------|
| `__FC_INSTANCE_ID__` | VM name |
| `__FC_LOCAL_HOSTNAME__` | VM name |

### firecracker-vm.service

| Placeholder | Source |
|-------------|--------|
| `{{FC_CONTROL_ROOT}}` | `/var/lib/firecracker/control` |
| `{{FC_RUNTIME_ROOT}}` | `/var/lib/firecracker` |

---

## VM name constraints

- Must match `^[a-z][a-z0-9-]*$`
- Derived tap name (`fc-<name>0`) must be <= 15 characters (Linux limit)
- Maximum effective name length: 11 characters

---

## Tests

```bash
for t in tests/*.sh; do bash "$t" || exit 1; done
```

| Suite | Coverage |
|-------|----------|
| `tests/image-build.sh` | Template build pipeline, partition extraction, fstab patching, seed injection |
| `tests/create-instance.sh` | Instance disk creation, resize, seed injection, metadata, networking, IP resolution |
| `tests/runtime-lifecycle.sh` | Config rendering, start/stop, SIGKILL escalation, cgroup cleanup, tap management, log bounding, PID safety |
| `tests/systemd-lifecycle.sh` | systemd unit install, operator sudo re-exec |
| `tests/install-host.sh` | Host package install, binary provisioning, preflight checks |
| `tests/ssh-command.sh` | fc-ssh argument construction, IP resolution, identity flags, copy-id mode |
