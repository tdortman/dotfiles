#!/usr/bin/env bash
set -euo pipefail

INTERFACE="@defaultInterface@"
NAMESPACE="vpn-run-ns"
VERBOSE=false
TEARDOWN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [--] COMMAND [ARGS...]

Run a command in an isolated network namespace that only egresses via a specific interface.
The namespace is created on first use and persists until explicitly torn down.
Multiple commands can run concurrently in the same namespace.

Options:
  -i, --interface NAME    VPN interface (default: @defaultInterface@)
  -n, --namespace NAME    Namespace name (default: vpn-run-ns)
  -t, --teardown          Destroy the namespace and clean up
  -v, --verbose           Verbose output
  -h, --help              Show this help

Examples:
  $(basename "$0") -- curl https://ipinfo.io
  $(basename "$0") -n wg0 -- firefox
  $(basename "$0") -t -n wg0          # tear down
EOF
    exit 1
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[vpn-run] $*" >&2 || true
    fi
}

error() {
    echo "[vpn-run] ERROR: $*" >&2
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run as root (use sudo)"
    fi
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
            --)
                shift
                break
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    require_root

    local setup_args=()
    [[ "$VERBOSE" == "true" ]] && setup_args+=("-v")
    setup_args+=("-i" "$INTERFACE" "-n" "$NAMESPACE")

    if [[ "$TEARDOWN" == "true" ]]; then
        vpn-run-setup "${setup_args[@]}" --teardown
        exit 0
    fi

    [[ $# -gt 0 ]] || error "No command specified. Use -h for help."

    # Ensure namespace exists (idempotent)
    vpn-run-setup "${setup_args[@]}"

    log "Running in namespace '$NAMESPACE': $*"

    local orig_user=""
    if [[ -n "${SUDO_USER:-}" ]]; then
        orig_user="$SUDO_USER"
    elif [[ $EUID -eq 0 ]]; then
        orig_user="root"
    else
        orig_user="$USER"
    fi

    ip netns exec "$NAMESPACE" \
        runuser -u "$orig_user" \
        --preserve-environment \
        -- "$@"
}

main "$@"
