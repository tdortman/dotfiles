#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="@namespace@"
START_UNITS="@startUnits@"
VERBOSE=false
TEARDOWN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [--] COMMAND [ARGS...]

Run a command directly inside a network namespace backed by a specific interface.

Options:
  -t, --teardown          Stop associated units, if configured
  -v, --verbose           Verbose output
  -h, --help              Show this help
EOF
    exit 1
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[@logPrefix@] $*" >&2 || true
    fi
}

error() {
    echo "[@logPrefix@] ERROR: $*" >&2
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run as root (use sudo)"
    fi
}

start_unit_args() {
    local units=()
    if [[ -n "$START_UNITS" ]]; then
        # Intentionally split the configured unit list into argv items.
        read -r -a units <<< "$START_UNITS"
    fi
    printf '%s\n' "${units[@]}"
}

main() {
    local start_units=()

    while [[ $# -gt 0 ]]; do
        case $1 in
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
    if [[ -n "$START_UNITS" ]]; then
        mapfile -t start_units < <(start_unit_args)
    fi

    if [[ "$TEARDOWN" == "true" ]]; then
        if (( ${#start_units[@]} > 0 )); then
            systemctl stop "${start_units[@]}"
            exit 0
        fi
        error "No teardown units configured"
    fi

    [[ $# -gt 0 ]] || error "No command specified. Use -h for help."

    if (( ${#start_units[@]} > 0 )); then
        systemctl start "${start_units[@]}"
    fi

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
