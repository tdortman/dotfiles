#!/usr/bin/env bash

DEFAULT_OUTPUT="@defaultOutput@"
DEFAULT_ICC_PROFILE="@defaultIccProfile@"

TOGGLE="${1:-toggle}"
OUTPUT="${2:-$DEFAULT_OUTPUT}"

# Variable juggling to make sure the default ICC profile is only applied
# to the default output in cases where multiple monitors are present.
declare ICCPROF_${DEFAULT_OUTPUT//-/_}="${DEFAULT_ICC_PROFILE}"
ICCPROF=ICCPROF_${OUTPUT//-/_}

# This is KDE Plasma 6 only for now
if [[ "$DESKTOP_SESSION" != "plasma" && "${DESKTOP_SESSION##*/}" != "plasma.desktop" ]] || [[ "${DISABLE_HDR_TOGGLING:-false}" == "true" ]]; then
    echo "Plasma desktop not active or DISABLE_HDR_TOGGLING has been set to true. Bailing."
    exit 1
fi

OUTPUT_HDR_STATE=$(kscreen-doctor -j | jq -r --arg name "$OUTPUT" '
  ( .outputs[] | select(.name == $name) |
    if has("hdr") then
      if .hdr then "enabled" else "disabled" end
    else
      "incapable"
    end
  ) // "incapable"
')

if [[ $OUTPUT_HDR_STATE == "incapable" ]]; then
    echo "Output $OUTPUT reports HDR is incapable or not supported.. Quitting..."
    exit 1
fi

function hdr_disable() {
    echo "$OUTPUT: Toggling HDR off"
    local ICCPROF_
    if [[ -n "${3:-}" ]]; then
        ICCPROF_=$3
    else
        ICCPROF_=${!ICCPROF}
    fi
    kscreen-doctor \
        output."$OUTPUT".hdr.disable \
        output."$OUTPUT".wcg.disable \
        output."$OUTPUT".iccprofile."$ICCPROF_" \
        >/dev/null 2>&1
}

function hdr_enable() {
    echo "$OUTPUT: Toggling HDR on"
    kscreen-doctor \
        output."$OUTPUT".hdr.enable \
        output."$OUTPUT".wcg.enable \
        >/dev/null 2>&1
}

show_usage() {
    cat <<EOF
Usage:
$(basename "$0") [enable|disable|toggle|help] [output] [ICC profile]

KDE Plasma desktop HDR toggler. Utilises kscreen-doctor.
To be used with launch wrapper scripts or command lines such as Steam or Lutris.

Steam:
'$(basename "$0") enable; %command%; $(basename "$0") disable'

Lutris:
Pre-launch script: '$(basename "$0") enable'
Post-exit script: '$(basename "$0") disable'

See 'kscreen-doctor -o' to list available outputs.
To disable this script globally, run: 'export DISABLE_HDR_TOGGLING=true'.
EOF
}

case $TOGGLE in
toggle)
    case $OUTPUT_HDR_STATE in
    enabled)
        hdr_disable "$@"
        ;;
    disabled)
        hdr_enable "$@"
        ;;
    *)
        echo "OUTPUT_HDR_STATE: '$OUTPUT_HDR_STATE' - Unexpected value. Bailing..."
        exit 2
        ;;
    esac
    ;;
enable)
    if [[ "$OUTPUT_HDR_STATE" == "disabled" ]]; then
        hdr_enable "$@"
    else
        echo "$OUTPUT: HDR is already enabled."
    fi
    ;;
disable)
    if [[ "$OUTPUT_HDR_STATE" == "enabled" ]]; then
        hdr_disable "$@"
    else
        echo "$OUTPUT: HDR is already disabled."
    fi
    ;;
help | h | -h | --help)
    show_usage
    ;;
*)
    printf "Unknown command: %s\n\n" "$1"
    show_usage
    exit 2
    ;;
esac

exit 0
