#!/usr/bin/env bash
set -euo pipefail

INTERFACE="@defaultInterface@"
NAMESPACE="vpn-run-ns"
VERBOSE=false
TEARDOWN=false

# veth pair addressing
VETH_HOST_CIDR="@vethHostAddress@"
VETH_NS_CIDR="@vethNsAddress@"

DISABLE_IPV6="@disableIPv6@"
DROP_NON_VPN="@dropNonVpnForward@"

VETH_HOST_IP="${VETH_HOST_CIDR%/*}"
VETH_NS_IP="${VETH_NS_CIDR%/*}"

HOST_DNS_TARGET="${VPN_RUN_HOST_DNS_TARGET:-127.0.0.54:53}"

DNS_TCP_PID=""
DNS_UDP_PID=""

LOCKDIR="/run/vpn-run-lock"
STATE_DIR="/run"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Set up or tear down a VPN-isolated network namespace.

Options:
  -i, --interface NAME    VPN interface (default: @defaultInterface@)
  -n, --namespace NAME    Namespace name (default: vpn-run-ns)
  -t, --teardown          Remove namespace and all associated rules
  -v, --verbose           Verbose output
  -h, --help              Show this help
EOF
    exit 1
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[vpn-run-setup] $*" >&2 || true
    fi
}

error() {
    echo "[vpn-run-setup] ERROR: $*" >&2
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run as root"
    fi
}

state_file() {
    echo "${STATE_DIR}/vpn-run-${NAMESPACE}.state"
}

acquire_lock() {
    mkdir -p "$LOCKDIR"
    exec 200>"$LOCKDIR/${NAMESPACE}.lock"
    flock 200
}

# Compute deterministic identifiers from namespace name.
# Sets: veth_host, veth_ns, route_table_id, rule_priority
declare -g veth_host="" veth_ns="" route_table_id="" rule_priority=""
compute_ids() {
    local cksum_out suffix
    cksum_out=$(printf '%s' "$NAMESPACE" | cksum | cut -d' ' -f1)
    suffix=$(printf '%s' "$cksum_out" | cut -c1-6)
    veth_host="vrnh-${suffix}"
    veth_ns="vrnn-${suffix}"
    route_table_id=$(((cksum_out % 55000) + 10000))
    rule_priority=$(((cksum_out % 20000) + 10000))
}

start_dns_bridge() {
    local dns_ip="${HOST_DNS_TARGET%:*}"
    local dns_port="${HOST_DNS_TARGET#*:}"

    log "Starting DNS bridge on ${VETH_HOST_IP}:53 -> ${dns_ip}:${dns_port} (UDP+TCP)"

    socat TCP4-LISTEN:53,bind="${VETH_HOST_IP}",fork,reuseaddr TCP4:"${dns_ip}":"${dns_port}" &
    DNS_TCP_PID=$!

    socat -T60 UDP4-LISTEN:53,bind="${VETH_HOST_IP}",fork,reuseaddr UDP4:"${dns_ip}":"${dns_port}" &
    DNS_UDP_PID=$!

    local i
    # shellcheck disable=SC2034
    for i in $(seq 1 40); do
        if ss -H -lntp 2>/dev/null | grep -qE "[[:space:]]${VETH_HOST_IP}:53[[:space:]].*socat"; then
            log "DNS TCP bridge listening"
            break
        fi
        sleep 0.05
    done
}

stop_dns_bridge() {
    local pid
    for pid in "${DNS_TCP_PID:-}" "${DNS_UDP_PID:-}"; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            local i
            # shellcheck disable=SC2034
            for i in $(seq 1 10); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
}

teardown() {
    local state_file
    state_file=$(state_file)

    log "Tearing down namespace '$NAMESPACE'"

    # Always compute deterministic identifiers so we can clean up
    # even if the state file is missing or stale.
    compute_ids

    # Load state if available (may override computed values)
    local saved_veth="" saved_route_table="" saved_rule_prio=""
    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file" || true
    fi

    # Stop DNS bridge (uses PIDs from state file if loaded)
    stop_dns_bridge

    # Remove nftables table (deterministic name)
    nft delete table ip "vpn-run-${NAMESPACE}" 2>/dev/null || true

    # Remove policy routing: try saved values first, then computed
    if [[ -n "${saved_rule_prio:-}" ]]; then
        ip rule del priority "$saved_rule_prio" 2>/dev/null || true
    fi
    ip rule del priority "$rule_priority" 2>/dev/null || true

    if [[ -n "${saved_route_table:-}" ]]; then
        ip route flush table "$saved_route_table" 2>/dev/null || true
    fi
    ip route flush table "$route_table_id" 2>/dev/null || true

    # Remove veth pair: try saved name first, then computed
    if [[ -n "${saved_veth:-}" ]]; then
        ip link del "$saved_veth" 2>/dev/null || true
    fi
    ip link del "$veth_host" 2>/dev/null || true

    # Remove namespace
    ip netns del "$NAMESPACE" 2>/dev/null || true

    # Remove per-netns files
    rm -f "/etc/netns/${NAMESPACE}/nsswitch.conf" "/etc/netns/${NAMESPACE}/resolv.conf" 2>/dev/null || true
    rmdir "/etc/netns/${NAMESPACE}" 2>/dev/null || true

    # Remove state file
    rm -f "$state_file" 2>/dev/null || true

    log "Teardown complete"
}

setup() {
    local state_file
    state_file=$(state_file)

    # Idempotency: already set up?
    if [[ -f "$state_file" ]]; then
        local saved_veth=""
        # shellcheck source=/dev/null
        source "$state_file" || true
        if [[ -n "${saved_veth:-}" ]] && ip link show "$saved_veth" >/dev/null 2>&1; then
            log "Namespace '$NAMESPACE' already set up (veth: $saved_veth)"
            return 0
        fi
        log "Stale state file detected, cleaning up"
        teardown
    fi

    # Unclean previous run?
    if ip netns list | grep -qE "^${NAMESPACE}(\\s|$)"; then
        log "Namespace exists without state file, cleaning up"
        teardown
    fi

    # Deterministic identifiers from namespace name
    compute_ids

    log "Using veth: $veth_host <-> $veth_ns"
    log "Route table: $route_table_id, rule priority: $rule_priority"

    # Verify VPN interface
    ip link show "$INTERFACE" >/dev/null 2>&1 || error "Interface '$INTERFACE' not found"

    # Create namespace
    ip netns add "$NAMESPACE" || error "Failed to create namespace '$NAMESPACE'"

    # Create veth pair
    ip link add "$veth_host" type veth peer name "$veth_ns"

    # Match MTU to VPN interface
    local mtu
    mtu=$(cat "/sys/class/net/${INTERFACE}/mtu" 2>/dev/null || echo 1420)
    ip link set dev "$veth_host" mtu "$mtu"
    ip link set dev "$veth_ns" mtu "$mtu"

    # Move one end into namespace
    ip link set "$veth_ns" netns "$NAMESPACE"

    # Configure host side
    ip addr add "$VETH_HOST_CIDR" dev "$veth_host"
    ip link set "$veth_host" up

    # Configure namespace side
    ip netns exec "$NAMESPACE" ip link set lo up
    ip netns exec "$NAMESPACE" ip addr add "$VETH_NS_CIDR" dev "$veth_ns"
    ip netns exec "$NAMESPACE" ip link set "$veth_ns" up

    # Disable IPv6
    if [[ "$DISABLE_IPV6" == "true" ]]; then
        log "Disabling IPv6 inside namespace"
        ip netns exec "$NAMESPACE" sysctl -q -w net.ipv6.conf.all.disable_ipv6=1 || true
        ip netns exec "$NAMESPACE" sysctl -q -w net.ipv6.conf.default.disable_ipv6=1 || true
    fi

    # Default route inside namespace
    ip netns exec "$NAMESPACE" ip route replace default via "$VETH_HOST_IP" dev "$veth_ns"

    # DNS resolver config for namespace
    mkdir -p "/etc/netns/${NAMESPACE}"
    cat >"/etc/netns/${NAMESPACE}/resolv.conf" <<EOF
nameserver ${VETH_HOST_IP}
options edns0
EOF

    # Host sysctls
    sysctl -q -w net.ipv4.ip_forward=1 || true
    sysctl -q -w net.ipv4.conf.all.rp_filter=0 || true
    sysctl -q -w net.ipv4.conf.default.rp_filter=0 || true
    sysctl -q -w net.ipv4.conf."${INTERFACE}".rp_filter=0 || true
    sysctl -q -w net.ipv4.conf."${veth_host}".rp_filter=0 || true
    sysctl -q -w net.ipv4.conf.all.route_localnet=1 || true
    sysctl -q -w net.ipv4.conf."${veth_host}".route_localnet=1 || true
    sysctl -q -w net.ipv4.conf."${INTERFACE}".route_localnet=1 || true

    # Build nftables ruleset (ip family, in same hook list as iptables-nft)
    local nft_table="vpn-run-${NAMESPACE}"
    local drop_rule=""

    if [[ "$DROP_NON_VPN" == "true" ]]; then
        drop_rule="iifname \"${veth_host}\" oifname != \"${INTERFACE}\" reject"
    fi

    # Remove any stale table first
    nft delete table ip "$nft_table" 2>/dev/null || true

    cat <<EOF | nft -f -
table ip ${nft_table} {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr ${VETH_NS_IP} oifname "${INTERFACE}" masquerade
    }
    chain forward {
        type filter hook forward priority filter - 200; policy accept;
        iifname "${veth_host}" oifname "${INTERFACE}" accept
        iifname "${INTERFACE}" oifname "${veth_host}" ct state established,related accept
        iifname "${veth_host}" udp dport 53 reject
        iifname "${veth_host}" tcp dport 53 reject
        ${drop_rule}
    }
    chain input {
        type filter hook input priority filter - 200; policy accept;
        iifname "${veth_host}" udp dport 53 accept
        iifname "${veth_host}" tcp dport 53 accept
    }
}
EOF

    # Policy routing: force source IP out via VPN interface
    ip route replace table "$route_table_id" default dev "$INTERFACE"
    ip rule del from "${VETH_NS_IP}/32" table "$route_table_id" 2>/dev/null || true
    ip rule add from "${VETH_NS_IP}/32" table "$route_table_id" priority "$rule_priority"

    # Release file lock before spawning socat children (they inherit fds)
    exec 200>&-

    # Start DNS bridge (socat proxy on veth host IP → host resolver)
    start_dns_bridge

    # Persist state
    cat >"$state_file" <<EOF
INTERFACE=${INTERFACE}
saved_veth=${veth_host}
VETH_NS=${veth_ns}
saved_route_table=${route_table_id}
saved_rule_prio=${rule_priority}
DNS_TCP_PID=${DNS_TCP_PID}
DNS_UDP_PID=${DNS_UDP_PID}
EOF

    log "Setup complete for namespace '$NAMESPACE'"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -i | --interface)
            INTERFACE="$2"
            shift 2
            ;;
        -n | --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -t | --teardown)
            TEARDOWN=true
            shift
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -h | --help)
            usage
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            error "Unexpected argument: $1"
            ;;
        esac
    done

    require_root
    acquire_lock

    if [[ "$TEARDOWN" == "true" ]]; then
        teardown
    else
        setup
    fi
}

main "$@"
