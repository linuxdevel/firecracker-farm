# firecracker-farm

Shell-based tooling for creating and managing persistent [Firecracker](https://firecracker-microvm.github.io/) microVMs on a Proxmox host.

## About Firecracker

[Firecracker](https://github.com/firecracker-microvm/firecracker) is an open-source virtual machine monitor (VMM) built by AWS for running multi-tenant container and serverless workloads. It uses Linux KVM to create lightweight microVMs that provide the security and isolation of traditional VMs with the speed and resource efficiency of containers.

Key characteristics:

- **Hardware-level isolation** -- Each microVM runs its own Linux kernel behind a KVM hardware boundary, unlike containers which share the host kernel.
- **Minimal device model** -- Firecracker exposes only a small number of emulated devices (virtio-net, virtio-block, serial, and a minimal keyboard controller), drastically reducing the attack surface compared to QEMU.
- **Fast startup** -- MicroVMs boot in under 125ms and require as little as 5 MiB of memory overhead.
- **Production-proven** -- Firecracker powers AWS Lambda and AWS Fargate, processing millions of workloads per second.

Firecracker is developed and maintained by Amazon Web Services under the Apache 2.0 license.

**Upstream resources:**

| Resource | Link |
|----------|------|
| GitHub repository | [firecracker-microvm/firecracker](https://github.com/firecracker-microvm/firecracker) |
| Official documentation | [firecracker-microvm.github.io](https://firecracker-microvm.github.io/) |
| Design overview | [design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md) |
| Getting started | [getting-started.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md) |
| Production host setup | [prod-host-setup.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/prod-host-setup.md) |
| Jailer documentation | [jailer.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/jailer.md) |
| Snapshotting | [snapshotting.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/versioning.md) |

## What firecracker-farm does

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

# 2. Create a VM instance (interactive — prompts for username, SSH key, and disk size)
fc-create myvm

# Or provide everything on the command line:
fc-create myvm --guest-user ops --ssh-key-file ~/.ssh/id_ed25519.pub --disk-size 20G --vcpus 2 --memory 2g

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
| `fc-create <name>` | Create a persistent VM instance (`--guest-user`, `--ssh-key-file`, `--disk-size`, `--vcpus`, `--memory`) |
| `fc-start <name>` | Start a VM (via systemd) |
| `fc-stop <name>` | Stop a VM (via systemd); supports `--force` for SIGKILL |
| `fc-status <name>` | Show detailed VM status (vCPUs, memory, disk, IP, uptime) |
| `fc-list` | List all VMs in a formatted table |
| `fc-ssh <name>` | SSH into a running VM (auto-resolves IP from MAC) |

All commands that require root re-exec themselves through passwordless `sudo` when invoked by a non-root operator.

Run any command with `-h` or `--help` for usage details.

### VM credentials

Each VM requires a **guest username** and **SSH public key**. These are injected into the VM via cloud-init at creation time.

When running interactively, `fc-create` prompts for both if not provided via flags. When running non-interactively (e.g. piped or scripted), both `--guest-user` and either `--ssh-key-file` or `--ssh-key` must be specified on the command line.

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

## Roadmap

### Network Isolation & L7 Proxy (planned)

- Isolated `fc-br0` bridge for Firecracker VMs (no direct internet access)
- Proxmox LXC gateway container with transparent mitmproxy
- nftables firewall: default-deny outbound, allow SSH inbound
- TLS interception with automatic CA certificate injection via cloud-init
- Credential rewriting (inject real API keys without exposing secrets to VMs)
- Per-VM domain allowlists

### Web Management GUI (planned)

- Dark-themed web dashboard running inside the LXC gateway (HTTPS on port 8443)
- Domain allowlist and credential rewrite rule editing per VM
- Live traffic log with WebSocket streaming and filtering
- nftables firewall rule editor with apply/rollback
- Service health monitoring and restart controls
- VM overview with DHCP lease table

## FAQ

### Why don't Firecracker VMs show up in the Proxmox web GUI?

Proxmox's web interface (PVE) is hardcoded to manage two types of guests: QEMU/KVM virtual machines (via `qm` and configs in `/etc/pve/qemu-server/`) and LXC containers (via `pct` and configs in `/etc/pve/lxc/`).

Firecracker is a completely separate Virtual Machine Monitor (VMM). Even though it uses the same underlying `/dev/kvm` hardware virtualization as QEMU, Proxmox has no awareness of Firecracker processes. To Proxmox, a running Firecracker microVM looks like an ordinary background Linux process (the `firecracker` binary managed by a systemd service) consuming CPU and RAM on the host.

Proxmox does not have a plugin architecture for alternative hypervisors, so there is no supported way to inject Firecracker VMs into the PVE interface without modifying Proxmox source code (which would break on every update).

**Planned workaround:** The firecracker-farm project will include its own web management GUI (running inside a proxy LXC gateway on port 8443) to provide a dedicated dashboard for monitoring and managing your microVMs. In the meantime, use `fc-list` and `fc-status <name>` from the command line to view your running VMs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting pull requests.

## License

Apache License 2.0. See [LICENSE](LICENSE) for the full text.
