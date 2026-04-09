# AGENTS.md

## Purpose

This repository automates creation of persistent Firecracker microVMs on a Linux host with KVM support.

The target outcome is:
- Firecracker-based microVMs running directly on the host
- Ubuntu guests on the existing LAN via `vmbr0`
- persistent per-instance writable rootfs disks
- default guest user: operator username (configurable via `--guest-user`)
- SSH access using the approved public key
- passwordless sudo for the configured guest user

## Safety Rules

- Do not perform destructive actions on existing host VMs, storage pools, bridges, or firewall configuration.
- Prefer additive changes only.
- Do not modify `/etc/network/interfaces` unless explicitly approved.
- Use the configured host bridge as the default unless the user approves something else. In the current environment, that bridge is `vmbr0`.
- Keep all Firecracker assets under dedicated Firecracker paths.
- Preserve logs and failed artifacts for debugging.
- Do not add destructive delete/cleanup flows by default.

## Current Host Facts

- Proxmox version: `8.4.17`
- Kernel: `6.8.12-20-pve`
- KVM device available: `/dev/kvm`
- Cgroups: `v2`
- Main bridge: `vmbr0`
- Host IP: `192.168.1.2/24`
- Gateway: `192.168.1.1`
- Storage pools: `local`, `local-lvm`, `zfsdisk`

## Project Defaults

- Bridge: `vmbr0` in the current tested environment
- Disk size: `20G`
- Memory: `1024M`
- vCPUs: `1`
- Runtime root: `/var/lib/firecracker`
- Logs root: `/var/log/firecracker`
- Binary root: `/opt/firecracker/bin`
- SSH key source default: operator's `~/.ssh/authorized_keys` (configurable via `--ssh-key-file`)

## Layout

Planned repository layout:
- `bin/` user-facing commands
- `lib/` shared shell helpers
- `templates/` systemd, cloud-init, and Firecracker config templates
- `docs/plans/` approved design and execution plans

## Implementation Approach

- Use Bash/shell for the first version.
- Prefer official Firecracker release binaries over source builds.
- Prefer official Ubuntu cloud images converted to raw templates.
- Clone and resize a per-instance disk at create time.
- Launch VMs with `jailer`.
- Manage lifecycle with systemd.

## Execution Notes

- If a task has an approved implementation plan, execute it in subagent-driven mode.
- Keep changes minimal and explicit.
- Verify behavior with focused commands before moving to the next task.
- When working against the current host, inspect first and change second.
