# firecracker-farm

Shell-based tooling for creating and managing persistent Firecracker microVMs on a Proxmox host.

## What it does

- Provisions Firecracker and jailer binaries on a Proxmox host
- Builds a reusable Ubuntu 24.04 cloud image template (bare ext4 rootfs)
- Creates persistent per-instance disks with configurable size
- Injects cloud-init seed (user, SSH key, hostname) directly into the rootfs
- Launches VMs via jailer with tap networking bridged to `vmbr0`
- Manages VM lifecycle through systemd template units
- Provides a configurable guest user with passwordless sudo and SSH key access

## Installation

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh | sudo bash
```

This downloads the latest release, installs it to `/opt/firecracker-farm/`, creates `fc-*` symlinks in `/usr/local/bin/`, and runs `fc-install-host` to set up Firecracker binaries, the guest kernel, and host config.

### With options

```bash
curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh \
  | sudo bash -s -- --guest-user myuser --ssh-key-file /home/myuser/.ssh/authorized_keys
```

### Pin a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/linuxdevel/firecracker-farm/main/install.sh \
  | sudo bash -s -- --version v1.0.0
```

### Manual install

1. Download the release tarball from the [Releases page](https://github.com/linuxdevel/firecracker-farm/releases)
2. Extract to `/opt/firecracker-farm/`
3. Run `bin/fc-install-host --guest-user myuser --ssh-key-file ~/.ssh/authorized_keys`

## Quick start

```bash
# 1. Build the Ubuntu template image
sudo bash -c 'source /opt/firecracker-farm/lib/image.sh && fc_image_build_template'

# 2. Create a VM instance (optionally set vCPUs and memory)
fc-create myvm --disk-size 20G --vcpus 2 --memory 2g

# 3. Start it (installs systemd unit, enables and starts the service)
fc-start myvm

# 4. SSH in (after ~30s for cloud-init + DHCP)
fc-ssh myvm

# 5. Check status
fc-status myvm

# 6. List all VMs
fc-list

# 7. Stop it
fc-stop myvm
```

## Commands

| Command | Description |
|---------|-------------|
| `fc-install-host` | Install host prerequisites, Firecracker binaries, guest kernel, and write host config |
| `fc-install-host --preflight` | Read-only host readiness check |
| `fc-create <name>` | Create a persistent VM instance (`--disk-size`, `--vcpus`, `--memory`) |
| `fc-start <name>` | Start a VM (via systemd) |
| `fc-stop <name>` | Stop a VM (via systemd); supports `--force` for SIGKILL |
| `fc-status <name>` | Show detailed VM status (vCPUs, memory, disk, IP, uptime) |
| `fc-list` | List all VMs in a formatted table |
| `fc-ssh <name>` | SSH into a running VM (auto-resolves IP from MAC) |

All commands that require root re-exec themselves through passwordless `sudo` when invoked by a non-root operator.

Run any command with `-h` or `--help` for usage details.

The first run of `fc-install-host` captures the operator's username and SSH key path into `/var/lib/firecracker/host.env`. All subsequent commands read this file automatically.

## Requirements

- Proxmox VE host with `/dev/kvm` and cgroups v2
- Linux bridge `vmbr0` (or override via `FC_DEFAULT_BRIDGE`)
- Passwordless sudo for the operator user
- DHCP server on the LAN (for guest IPv4)

### Host packages

Installed automatically by `fc-install-host`:

- `curl`, `jq`, `qemu-utils`, `e2fsprogs`
- Optional: `libguestfs-tools` (for offline image customization)

## Layout

```
bin/                   User-facing commands
lib/                   Shared shell libraries
  common.sh            Logging, argument handling, sudo re-exec
  config.sh            Default platform settings
  image.sh             Template build and instance disk creation
  firecracker.sh       Config rendering, jailer launch, start/stop
  network.sh           Tap/bridge networking, MAC derivation
templates/             Firecracker config, cloud-init, systemd unit templates
tests/                 Shell-based test suites
docs/plans/            Design and implementation plans
```

## Defaults

| Setting | Default | Override |
|---------|---------|----------|
| Bridge | `vmbr0` | `FC_DEFAULT_BRIDGE` |
| Disk size | `20G` | `--disk-size` flag or `FC_DEFAULT_DISK_SIZE` |
| RAM | `1024 MiB` | `FC_DEFAULT_MEMORY_MIB` |
| vCPUs | `1` | `FC_DEFAULT_VCPUS` |
| Runtime root | `/var/lib/firecracker` | `FC_RUNTIME_ROOT` |
| Log root | `/var/log/firecracker` | `FC_LOG_ROOT` |
| Binary root | `/opt/firecracker/bin` | `FC_BINARY_ROOT` |
| SSH key source | `~/.ssh/authorized_keys` (operator) | `--ssh-key-file` on `fc-install-host` or `FC_SSH_KEY_FILE` |
| Guest user | operator username | `--guest-user` on `fc-install-host` or `FC_GUEST_USER` |

## How it works

### Template build

The template pipeline downloads an official Ubuntu cloud image, converts it to raw, extracts the root partition into a standalone ext4 filesystem, and patches `/etc/fstab` to remove references to partitions that don't exist in the Firecracker environment. The result is stored at `/var/lib/firecracker/images/ubuntu-template.raw`.

### Instance creation

`fc-create` clones the template into a per-instance disk under `/var/lib/firecracker/vms/<name>/`, resizes it with `qemu-img` + `resize2fs`, then loop-mounts the disk to inject cloud-init seed files directly into `/var/lib/cloud/seed/nocloud/`. This avoids the need for a separate seed drive (the Firecracker CI kernel lacks iso9660 and vfat built-in). Network identity metadata (tap name, MAC, bridge) is also recorded.

### VM launch

`fc-start` installs a systemd template unit (`firecracker@.service`), syncs a stable copy of the control scripts into `/var/lib/firecracker/control/`, and enables the instance service. The service calls back into `fc-start --direct <name>` which:

1. Creates a tap device and attaches it to the bridge
2. Renders the Firecracker JSON config from metadata
3. Hard-links the persistent rootfs into the jailer chroot (writes survive restarts)
4. Launches Firecracker via jailer with bounded log capture
5. Records PID and runtime state

### Networking

Each VM gets a deterministic tap name (`fc-<name>0`) and a stable locally-administered MAC address derived from the instance name. The tap is bridged to `vmbr0`. Inside the guest, cloud-init configures netplan with DHCP on the matching MAC.

## Tests

```bash
# Run all test suites
for t in tests/*.sh; do bash "$t" || exit 1; done
```

Test suites:
- `tests/image-build.sh` — template build pipeline
- `tests/create-instance.sh` — instance disk creation, seed injection, networking, IP resolution
- `tests/runtime-lifecycle.sh` — config rendering, start/stop, tap management, log bounding, SIGKILL escalation
- `tests/systemd-lifecycle.sh` — systemd unit install, operator sudo re-exec
- `tests/install-host.sh` — host package install, binary provisioning
- `tests/ssh-command.sh` — fc-ssh argument construction, IP resolution, copy-id

## Safety

- Never modifies existing Proxmox VMs, storage pools, bridges, or firewall rules
- Never modifies `/etc/network/interfaces`
- All Firecracker assets are kept under dedicated paths (`/var/lib/firecracker`, `/opt/firecracker`)
- No destructive delete/cleanup commands in v1
- Input validation rejects invalid VM names, overlong tap names, unsafe PID/tap values

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting pull requests.

## License

Apache License 2.0. See [LICENSE](LICENSE) for the full text.
