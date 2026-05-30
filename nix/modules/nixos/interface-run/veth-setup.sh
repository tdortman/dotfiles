#!/usr/bin/env bash
set -euo pipefail

INTERFACE="@defaultInterface@"
NAMESPACE="@logPrefix@-ns"
VERBOSE=false
TEARDOWN=false

VETH_HOST_IP=""
VETH_NS_IP=""
VETH_HOST_CIDR=""
VETH_NS_CIDR=""

DISABLE_IPV6="@disableIPv6@"
DROP_NON_IFACE="@dropNonInterfaceForward@"

HOST_DNS_TARGET="${VPN_RUN_HOST_DNS_TARGET:-127.0.0.53:53}"
SNAT_SOURCE="${VPN_RUN_SNAT_SOURCE:-}"

DNS_TCP_PID=""
DNS_UDP_PID=""

LOCKDIR="/run/interface-run-lock"
STATE_DIR="/run"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Set up or tear down an interface-isolated network namespace.

Options:
  -i, --interface NAME    Interface (default: @defaultInterface@)
  -n, --namespace NAME    Namespace name (default: @logPrefix@-ns)
  -t, --teardown          Remove namespace and all associated rules
  -v, --verbose           Verbose output
  -h, --help              Show this help
EOF
    exit 1
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[@logPrefix@-setup] $*" >&2 || true
    fi
}

error() {
    echo "[@logPrefix@-setup] ERROR: $*" >&2
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run as root"
    fi
}

state_file() {
    echo "${STATE_DIR}/interface-run-${NAMESPACE}.state"
}

acquire_lock() {
    mkdir -p "$LOCKDIR"
    exec 200>"$LOCKDIR/${NAMESPACE}.lock"
    flock 200
}

declare -g veth_host="" veth_ns="" route_table_id="" rule_priority=""
compute_ids() {
    local cksum_out suffix
    cksum_out=$(printf '%s' "$NAMESPACE" | cksum | cut -d' ' -f1)
    suffix=$(printf '%s' "$cksum_out" | cut -c1-6)
    veth_host="irnh-${suffix}"
    veth_ns="irnn-${suffix}"
    route_table_id=$(((cksum_out % 55000) + 10000))
    rule_priority=$(((cksum_out % 20000) + 10000))

    local offset=$(( (cksum_out % 16384) * 4 ))
    local h3=$(( offset / 256 ))
    local h4=$(( offset % 256 ))
    VETH_HOST_IP="198.18.${h3}.${h4}"
    VETH_NS_IP="198.18.${h3}.$(( h4 + 1 ))"
    VETH_HOST_CIDR="${VETH_HOST_IP}/30"
    VETH_NS_CIDR="${VETH_NS_IP}/30"
}

dns_bridge_listening() {
    ss -H -lntp 2>/dev/null | grep -qE "[[:space:]]${VETH_HOST_IP}:53[[:space:]].*socat" && \
    ss -H -lnup 2>/dev/null | grep -qE "[[:space:]]${VETH_HOST_IP}:53[[:space:]].*socat"
}

dns_target_ip() {
    printf '%s\n' "${HOST_DNS_TARGET%:*}"
}

dns_target_port() {
    printf '%s\n' "${HOST_DNS_TARGET#*:}"
}

use_dns_bridge() {
    local dns_ip
    dns_ip=$(dns_target_ip)
    [[ "$dns_ip" == 127.* ]]
}

setup_is_healthy() {
    local state_file want_iface saved_veth=""
    state_file=$(state_file)
    want_iface="$INTERFACE"

    [[ -f "$state_file" ]] || return 1
    # shellcheck source=/dev/null
    source "$state_file" || return 1

    [[ "${INTERFACE}" == "$want_iface" ]] || return 1
    [[ -n "${saved_veth:-}" ]] || return 1
    [[ "${saved_dns_target:-}" == "$HOST_DNS_TARGET" ]] || return 1
    [[ "${saved_snat_source:-}" == "$SNAT_SOURCE" ]] || return 1
    ip netns list 2>/dev/null | grep -qE "^${NAMESPACE}(\s|$)" || return 1
    ip netns exec "$NAMESPACE" true >/dev/null 2>&1 || return 1
    ip link show "$saved_veth" >/dev/null 2>&1 || return 1
    ip link show "$want_iface" >/dev/null 2>&1 || return 1
    nft list table ip "interface-run-${NAMESPACE}" >/dev/null 2>&1 || return 1
    ip rule list | grep -qF "from ${VETH_NS_IP}" || return 1
    ip route show table "${saved_route_table:-$route_table_id}" 2>/dev/null | grep -qF "dev ${want_iface}" || return 1
    if use_dns_bridge; then
        dns_bridge_listening || return 1
    fi
    return 0
}

ensure_dns_bridge() {
    local state_file
    state_file=$(state_file)

    if ! use_dns_bridge; then
        return 0
    fi

    if dns_bridge_listening; then
        return 0
    fi

    log "DNS bridge not listening, restarting"
    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file" || true
    fi
    stop_dns_bridge
    start_dns_bridge

    cat >"$state_file" <<EOF
INTERFACE=${INTERFACE}
saved_veth=${saved_veth:-$veth_host}
VETH_NS=${VETH_NS:-$veth_ns}
saved_route_table=${saved_route_table:-$route_table_id}
saved_rule_prio=${saved_rule_prio:-$rule_priority}
saved_dns_target=${HOST_DNS_TARGET}
saved_snat_source=${SNAT_SOURCE}
DNS_TCP_PID=${DNS_TCP_PID}
DNS_UDP_PID=${DNS_UDP_PID}
EOF
}

vpn_default_route_args() {
    local iface_src
    iface_src="$SNAT_SOURCE"
    if [[ -z "$iface_src" ]]; then
        iface_src=$(ip -4 -o addr show dev "$INTERFACE" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    if [[ -n "$iface_src" ]]; then
        echo "default dev $INTERFACE src $iface_src"
    else
        echo "default dev $INTERFACE"
    fi
}

start_dns_bridge() {
    local dns_ip dns_port i
    dns_ip=$(dns_target_ip)
    dns_port=$(dns_target_port)

    log "Starting DNS bridge on ${VETH_HOST_IP}:53 -> ${dns_ip}:${dns_port} (UDP+TCP)"

    socat TCP4-LISTEN:53,bind="${VETH_HOST_IP}",fork,reuseaddr TCP4:"${dns_ip}":"${dns_port}" &
    DNS_TCP_PID=$!

    socat -T60 UDP4-LISTEN:53,bind="${VETH_HOST_IP}",fork,reuseaddr UDP4:"${dns_ip}":"${dns_port}" &
    DNS_UDP_PID=$!

    for i in $(seq 1 40); do
        if dns_bridge_listening; then
            log "DNS bridge listening"
            break
        fi
        sleep 0.05
    done
}

stop_dns_bridge() {
    local pid i
    for pid in "${DNS_TCP_PID:-}" "${DNS_UDP_PID:-}"; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o comm= 2>/dev/null | grep -qxF socat; then
            kill "$pid" 2>/dev/null || true
            # shellcheck disable=SC2034
            for i in $(seq 1 10); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    if command -v pkill &>/dev/null; then
        pkill -f "socat.*bind=${VETH_HOST_IP}:53" 2>/dev/null || true
    fi
}

teardown() {
    local state_file saved_veth="" saved_route_table="" saved_rule_prio=""
    state_file=$(state_file)
    log "Tearing down namespace '$NAMESPACE'"
    compute_ids
    if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file" || true
    fi
    stop_dns_bridge
    nft delete table ip "interface-run-${NAMESPACE}" 2>/dev/null || true
    if [[ -n "${saved_rule_prio:-}" ]]; then
        ip rule del priority "$saved_rule_prio" 2>/dev/null || true
    fi
    ip rule del priority "$rule_priority" 2>/dev/null || true
    if [[ -n "${saved_route_table:-}" ]]; then
        ip route flush table "$saved_route_table" 2>/dev/null || true
    fi
    ip route flush table "$route_table_id" 2>/dev/null || true
    if [[ -n "${saved_veth:-}" ]]; then
        ip link del "$saved_veth" 2>/dev/null || true
    fi
    ip link del "$veth_host" 2>/dev/null || true
    ip netns del "$NAMESPACE" 2>/dev/null || true
    rm -f "/etc/netns/${NAMESPACE}/nsswitch.conf" "/etc/netns/${NAMESPACE}/resolv.conf" 2>/dev/null || true
    rmdir "/etc/netns/${NAMESPACE}" 2>/dev/null || true
    rm -f "$state_file" 2>/dev/null || true
    log "Teardown complete"
}

setup() {
    local state_file mtu ns_nameserver nft_table drop_rule nat_rule dns_forward_rules dns_input_rules
    state_file=$(state_file)
    compute_ids

    if setup_is_healthy; then
        # shellcheck source=/dev/null
        source "$state_file" || true
        log "Namespace '$NAMESPACE' already set up (veth: ${saved_veth:-$veth_host}, interface: $INTERFACE)"
        ensure_dns_bridge
        return 0
    fi

    if [[ -f "$state_file" ]] || ip netns list | grep -qE "^${NAMESPACE}(\s|$)"; then
        if [[ -n "$(ip netns pids "$NAMESPACE" 2>/dev/null)" ]]; then
            log "Namespace '$NAMESPACE' has active PIDs, skipping teardown"
            return 0
        fi
        log "Stale or incomplete setup, reinitializing"
        teardown
        compute_ids
    fi

    log "Using veth: $veth_host <-> $veth_ns"
    log "Route table: $route_table_id, rule priority: $rule_priority"

    ip link show "$INTERFACE" >/dev/null 2>&1 || error "Interface '$INTERFACE' not found"

    ip netns add "$NAMESPACE" || error "Failed to create namespace '$NAMESPACE'"
    ip link add "$veth_host" type veth peer name "$veth_ns"

    mtu=$(cat "/sys/class/net/${INTERFACE}/mtu" 2>/dev/null || echo 1420)
    ip link set dev "$veth_host" mtu "$mtu"
    ip link set dev "$veth_ns" mtu "$mtu"
    ip link set "$veth_ns" netns "$NAMESPACE"

    ip addr add "$VETH_HOST_CIDR" dev "$veth_host"
    ip link set "$veth_host" up

    ip netns exec "$NAMESPACE" ip link set lo up
    ip netns exec "$NAMESPACE" ip addr add "$VETH_NS_CIDR" dev "$veth_ns"
    ip netns exec "$NAMESPACE" ip link set "$veth_ns" up

    if [[ "$DISABLE_IPV6" == "true" ]]; then
        log "Disabling IPv6 inside namespace"
        ip netns exec "$NAMESPACE" sysctl -q -w net.ipv6.conf.all.disable_ipv6=1 || true
        ip netns exec "$NAMESPACE" sysctl -q -w net.ipv6.conf.default.disable_ipv6=1 || true
    fi

    ip netns exec "$NAMESPACE" ip route replace default via "$VETH_HOST_IP" dev "$veth_ns"

    ns_nameserver="$VETH_HOST_IP"
    if ! use_dns_bridge; then
        ns_nameserver=$(dns_target_ip)
        log "Using direct DNS from namespace to ${ns_nameserver}:$(dns_target_port)"
    fi

    mkdir -p "/etc/netns/${NAMESPACE}"
    cat >"/etc/netns/${NAMESPACE}/nsswitch.conf" <<EOF
passwd: files systemd
group: files systemd
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
EOF
    cat >"/etc/netns/${NAMESPACE}/resolv.conf" <<EOF
nameserver ${ns_nameserver}
options edns0
EOF

    sysctl -q -w net.ipv4.ip_forward=1 || true
    sysctl -q -w net.ipv4.conf.all.rp_filter=0 || true
    sysctl -q -w net.ipv4.conf.default.rp_filter=0 || true
    sysctl -q -w net.ipv4.conf."${INTERFACE}".rp_filter=0 || true
    sysctl -q -w net.ipv4.conf."${veth_host}".rp_filter=0 || true
    sysctl -q -w net.ipv4.conf.all.route_localnet=1 || true
    sysctl -q -w net.ipv4.conf."${veth_host}".route_localnet=1 || true
    sysctl -q -w net.ipv4.conf."${INTERFACE}".route_localnet=1 || true

    nft_table="interface-run-${NAMESPACE}"
    drop_rule=""
    nat_rule="ip saddr ${VETH_NS_IP} oifname \"${INTERFACE}\" masquerade"
    dns_forward_rules=""
    dns_input_rules=""

    if [[ "$DROP_NON_IFACE" == "true" ]]; then
        drop_rule="iifname \"${veth_host}\" oifname != \"${INTERFACE}\" reject"
    fi

    if [[ -n "$SNAT_SOURCE" ]]; then
        nat_rule="ip saddr ${VETH_NS_IP} oifname \"${INTERFACE}\" snat to ${SNAT_SOURCE}"
        log "SNAT source: ${SNAT_SOURCE}"
    fi

    if use_dns_bridge; then
        dns_forward_rules="        iifname \"${veth_host}\" udp dport 53 reject
        iifname \"${veth_host}\" tcp dport 53 reject"
        dns_input_rules="        iifname \"${veth_host}\" udp dport 53 accept
        iifname \"${veth_host}\" tcp dport 53 accept"
    fi

    nft delete table ip "$nft_table" 2>/dev/null || true
    cat <<EOF | nft -f -
table ip ${nft_table} {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ${nat_rule}
    }
    chain forward {
        type filter hook forward priority filter - 200; policy accept;
        iifname "${veth_host}" oifname "${INTERFACE}" accept
        iifname "${INTERFACE}" oifname "${veth_host}" ct state established,related accept
${dns_forward_rules}
        ${drop_rule}
    }
    chain input {
        type filter hook input priority filter - 200; policy accept;
${dns_input_rules}
    }
}
EOF

    # shellcheck disable=SC2046
    ip route replace table "$route_table_id" $(vpn_default_route_args)
    ip rule del from "${VETH_NS_IP}/32" table "$route_table_id" 2>/dev/null || true
    ip rule add from "${VETH_NS_IP}/32" table "$route_table_id" priority "$rule_priority"

    exec 200>&-
    if use_dns_bridge; then
        start_dns_bridge
    fi

    cat >"$state_file" <<EOF
INTERFACE=${INTERFACE}
saved_veth=${veth_host}
VETH_NS=${veth_ns}
saved_route_table=${route_table_id}
saved_rule_prio=${rule_priority}
saved_dns_target=${HOST_DNS_TARGET}
saved_snat_source=${SNAT_SOURCE}
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
