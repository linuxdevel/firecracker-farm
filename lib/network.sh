#!/usr/bin/env bash

if [[ -n "${FC_NETWORK_SH_LOADED:-}" ]]; then
  return 0
fi
readonly FC_NETWORK_SH_LOADED=1

# shellcheck source=./common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fc_load_config

fc_network_bridge_name() {
  printf '%s\n' "$FC_DEFAULT_BRIDGE"
}

fc_network_max_interface_name_length() {
  printf '15\n'
}

fc_network_tap_name() {
  local vm_name=$1

  printf 'fc-%s0\n' "$vm_name"
}

fc_network_validate_tap_name() {
  local tap_name=$1
  local max_length

  max_length=$(fc_network_max_interface_name_length) || return 1
  if (( ${#tap_name} <= max_length )); then
    return 0
  fi

  fc_error "derived tap name '$tap_name' exceeds Linux interface name limit (${max_length} characters)"
  return 1
}

fc_network_validate_vm_name() {
  local vm_name=$1
  local tap_name

  tap_name=$(fc_network_tap_name "$vm_name") || return 1
  fc_network_validate_tap_name "$tap_name"
}

fc_network_mac_address() {
  local vm_name=$1
  local hash

  hash=$(printf '%s' "$vm_name" | sha256sum | cut -c1-10) || return 1
  printf '02:%s:%s:%s:%s:%s\n' \
    "${hash:0:2}" \
    "${hash:2:2}" \
    "${hash:4:2}" \
    "${hash:6:2}" \
    "${hash:8:2}"
}

fc_network_create_tap() {
  local tap_name=$1
  # Note: mac_address parameter is accepted for API compatibility but
  # NOT applied to the tap device. The guest MAC is set inside Firecracker's
  # VM config. Setting the host-side tap to the same MAC confuses the Linux
  # bridge — it misroutes return traffic to the host stack instead of
  # forwarding it through the tap to the VM.
  local _mac_address=$2

  ip tuntap add dev "$tap_name" mode tap
}

fc_network_attach_tap_to_bridge() {
  local tap_name=$1
  local bridge_name=$2

  ip link set "$tap_name" master "$bridge_name"
}

fc_network_set_tap_up() {
  local tap_name=$1

  ip link set "$tap_name" up
}

fc_network_delete_tap() {
  local tap_name=$1

  ip link delete "$tap_name"
}

fc_network_write_instance_metadata() {
  local metadata_path=$1
  local tap_name=$2
  local mac_address=$3
  local bridge_name=$4

  cat >> "$metadata_path" <<EOF
TAP_NAME=$tap_name
MAC_ADDRESS=$mac_address
BRIDGE_NAME=$bridge_name
EOF
}

fc_network_create_instance_tap() {
  local vm_name=$1
  local metadata_path=$2
  local tap_name
  local mac_address
  local bridge_name

  tap_name=$(fc_network_tap_name "$vm_name") || return 1
  fc_network_validate_tap_name "$tap_name" || return 1
  mac_address=$(fc_network_mac_address "$vm_name") || return 1
  bridge_name=$(fc_network_bridge_name) || return 1

  fc_network_create_tap "$tap_name" "$mac_address" || return 1
  if ! fc_network_attach_tap_to_bridge "$tap_name" "$bridge_name"; then
    fc_network_delete_tap "$tap_name" || true
    return 1
  fi
  if ! fc_network_set_tap_up "$tap_name"; then
    fc_network_delete_tap "$tap_name" || true
    return 1
  fi
  if ! fc_network_write_instance_metadata "$metadata_path" "$tap_name" "$mac_address" "$bridge_name"; then
    fc_network_delete_tap "$tap_name" || true
    return 1
  fi
}

fc_network_prepare_instance_metadata() {
  local vm_name=$1
  local metadata_path=$2
  local tap_name
  local mac_address
  local bridge_name

  tap_name=$(fc_network_tap_name "$vm_name") || return 1
  fc_network_validate_tap_name "$tap_name" || return 1
  mac_address=$(fc_network_mac_address "$vm_name") || return 1
  bridge_name=$(fc_network_bridge_name) || return 1

  fc_network_write_instance_metadata "$metadata_path" "$tap_name" "$mac_address" "$bridge_name"
}

fc_network_resolve_guest_ip() {
    local mac_address=$1
    local bridge_name=${2:-$FC_DEFAULT_BRIDGE}
    local ip

    # Check ARP/neighbor table for this MAC
    ip=$(ip neigh show dev "$bridge_name" 2>/dev/null \
        | awk -v mac="$mac_address" 'tolower($0) ~ tolower(mac) && /REACHABLE|STALE|DELAY|PROBE/ { print $1; exit }')

    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return 0
    fi

    # Try arping to populate the neighbor table, then retry
    if command -v arping >/dev/null 2>&1; then
        arping -c 1 -w 1 -I "$bridge_name" -D 255.255.255.255 >/dev/null 2>&1 || true
        sleep 0.3
        ip=$(ip neigh show dev "$bridge_name" 2>/dev/null \
            | awk -v mac="$mac_address" 'tolower($0) ~ tolower(mac) && /REACHABLE|STALE|DELAY|PROBE/ { print $1; exit }')
        if [[ -n "$ip" ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    return 1
}
