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

fc_network_resolve_guest_ip_from_neigh() {
    local mac_address=$1
    local bridge_name=$2
    local prefer_ipv4=${3:-false}

    # Collect all IPs for this MAC, prefer IPv4 (contains '.') over
    # link-local IPv6 (contains ':').  When prefer_ipv4 is "true", only
    # return an IPv6 address if no IPv4 is available AND a subsequent
    # active-discovery pass has already been attempted.
    ip neigh show dev "$bridge_name" 2>/dev/null \
        | awk -v mac="$mac_address" -v pref="$prefer_ipv4" '
            tolower($0) ~ tolower(mac) && /REACHABLE|STALE|DELAY|PROBE/ {
                if ($1 ~ /\./) { ipv4 = $1 }
                else if (ipv6 == "") { ipv6 = $1 }
            }
            END {
                if (ipv4 != "") print ipv4
                else if (pref != "true" && ipv6 != "") print ipv6
            }'
}

fc_network_cidr_broadcast() {
    local cidr=$1
    local ip prefix a b c d ip_int host_bits host_mask broadcast

    IFS=/ read -r ip prefix <<< "$cidr"
    IFS=. read -r a b c d <<< "$ip"

    ip_int=$(( (a << 24) | (b << 16) | (c << 8) | d ))
    host_bits=$(( 32 - prefix ))
    host_mask=$(( (1 << host_bits) - 1 ))
    broadcast=$(( ip_int | host_mask ))

    printf '%d.%d.%d.%d\n' \
        $(( (broadcast >> 24) & 0xFF )) \
        $(( (broadcast >> 16) & 0xFF )) \
        $(( (broadcast >> 8) & 0xFF )) \
        $(( broadcast & 0xFF ))
}

fc_network_resolve_guest_ip() {
    local mac_address=$1
    local bridge_name=${2:-$FC_DEFAULT_BRIDGE}
    local ip

    # Check ARP/neighbor table for this MAC (IPv4 only on first pass — an
    # IPv6 link-local address is always present and would short-circuit the
    # active-discovery step that finds the real IPv4 address).
    ip=$(fc_network_resolve_guest_ip_from_neigh "$mac_address" "$bridge_name" true)

    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return 0
    fi

    # The host's ARP cache only contains IPs it has communicated with directly.
    # VMs that talk only to the router never appear. Trigger an ARP sweep of the
    # bridge subnet so all connected hosts expose their IP→MAC mapping.
    local bridge_cidr
    bridge_cidr=$(ip -4 addr show dev "$bridge_name" 2>/dev/null \
        | awk '/inet / {print $2; exit}')
    if [[ -n "$bridge_cidr" ]]; then
        # nmap -PR sends ARP who-has for every IP in the subnet. Its raw-socket
        # approach reliably discovers hosts but does NOT populate the kernel
        # neighbor cache, so we parse its output directly for the MAC→IP mapping.
        if command -v nmap >/dev/null 2>&1; then
            ip=$(nmap -PR -sn -n "$bridge_cidr" 2>/dev/null \
                | awk -v mac="$mac_address" '
                    /Nmap scan report for/ { current_ip = $NF }
                    /MAC Address:/ {
                        gsub(/:/, ":", $3)
                        if (tolower($3) == tolower(mac)) { print current_ip; exit }
                    }')
            if [[ -n "$ip" ]]; then
                printf '%s\n' "$ip"
                return 0
            fi
        fi

        # Fallback: broadcast ping goes through the kernel stack and populates
        # the neighbor cache directly.
        local broadcast
        broadcast=$(fc_network_cidr_broadcast "$bridge_cidr")
        if [[ -n "$broadcast" ]]; then
            ping -b -c 3 -i 0.1 -W 1 "$broadcast" >/dev/null 2>&1 || true
        fi
        sleep 0.3
        ip=$(fc_network_resolve_guest_ip_from_neigh "$mac_address" "$bridge_name")
        if [[ -n "$ip" ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    # Last resort: accept an IPv6 address from the neighbor table if no IPv4
    # was found after all active-discovery attempts.
    ip=$(fc_network_resolve_guest_ip_from_neigh "$mac_address" "$bridge_name")
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return 0
    fi

    return 1
}
