#!/usr/bin/env bash

DEFAULT_OUTPUT=@defaultOutput@
DEFAULT_ICC_PROFILE=@defaultIccProfile@

TOGGLE="${1:-toggle}"
EXPLICIT_OUTPUT="${2:-}"
EXPLICIT_ICC_PROFILE="${3:-}"

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

If [output] is omitted, the configured default output is used, or the
current primary output when no default is configured.
See 'kscreen-doctor -o' to list available outputs.
To disable this script globally, run: 'export DISABLE_HDR_TOGGLING=true'.
EOF
}

# Help must work without a desktop session.
case "$TOGGLE" in
help | h | -h | --help)
    show_usage
    exit 0
    ;;
esac

# This is KDE Plasma 6 only for now
_session="${DESKTOP_SESSION:-}"
if [[ "$_session" != "plasma" && "${_session##*/}" != "plasma.desktop" ]] || [[ "${DISABLE_HDR_TOGGLING:-false}" == "true" ]]; then
    echo "Plasma desktop not active or DISABLE_HDR_TOGGLING has been set to true. Bailing."
    exit 1
fi

# Single kscreen-doctor snapshot for primary resolution and HDR state.
# Pinned schema (libkscreen 6.7.5 ConfigSerializer::serializeOutput):
# the primary output has priority == 1 (Doctor::setPrimary sets priority 1),
# and the "hdr" key exists only on HDR-capable outputs.
if ! KSCREEN_SNAPSHOT=$(kscreen-doctor -j); then
    echo "hdr-toggle: kscreen-doctor -j failed, cannot read output state." >&2
    exit 1
fi

PRIMARY_OUTPUT=$(jq -r '[.outputs[] | select(.connected == true and .enabled == true and .priority == 1) | .name] | first // empty' <<<"$KSCREEN_SNAPSHOT")

if [[ -n "$EXPLICIT_OUTPUT" ]]; then
    OUTPUT="$EXPLICIT_OUTPUT"
elif [[ -n "$DEFAULT_OUTPUT" ]]; then
    OUTPUT="$DEFAULT_OUTPUT"
elif [[ -n "$PRIMARY_OUTPUT" ]]; then
    OUTPUT="$PRIMARY_OUTPUT"
else
    echo "hdr-toggle: no enabled, connected primary output found; pass an output explicitly." >&2
    exit 1
fi

RESOLVED_DEFAULT="${DEFAULT_OUTPUT:-$PRIMARY_OUTPUT}"

MATCHED_STATES=$(jq -r --arg name "$OUTPUT" '.outputs[] | select(.name == $name) | if has("hdr") then (if .hdr then "enabled" else "disabled" end) else "incapable" end' <<<"$KSCREEN_SNAPSHOT")
OUTPUT_HDR_STATE="${MATCHED_STATES%%$'\n'*}"

if [[ -z "$OUTPUT_HDR_STATE" ]]; then
    echo "hdr-toggle: output '$OUTPUT' not found. See 'kscreen-doctor -o' for available outputs." >&2
    exit 1
fi

if [[ "$OUTPUT_HDR_STATE" == "incapable" ]]; then
    echo "Output $OUTPUT reports HDR is incapable or not supported. Quitting..." >&2
    exit 1
fi

# The default ICC profile applies only to the resolved default output and
# only when set; an explicit profile always wins. Empty means skip ICC.
ICC_ARGS=()
if [[ -n "$EXPLICIT_ICC_PROFILE" ]]; then
    ICC_ARGS=(output."$OUTPUT".iccprofile."$EXPLICIT_ICC_PROFILE")
elif [[ -n "$DEFAULT_ICC_PROFILE" && -n "$RESOLVED_DEFAULT" && "$OUTPUT" == "$RESOLVED_DEFAULT" ]]; then
    ICC_ARGS=(output."$OUTPUT".iccprofile."$DEFAULT_ICC_PROFILE")
fi

hdr_disable() {
    echo "$OUTPUT: Toggling HDR off"
    kscreen-doctor \
        output."$OUTPUT".hdr.disable \
        output."$OUTPUT".wcg.disable \
        "${ICC_ARGS[@]}"
}

hdr_enable() {
    echo "$OUTPUT: Toggling HDR on"
    kscreen-doctor \
        output."$OUTPUT".hdr.enable \
        output."$OUTPUT".wcg.enable
}

case "$TOGGLE" in
toggle)
    case "$OUTPUT_HDR_STATE" in
    enabled)
        hdr_disable
        ;;
    disabled)
        hdr_enable
        ;;
    *)
        echo "OUTPUT_HDR_STATE: '$OUTPUT_HDR_STATE' - Unexpected value. Bailing..."
        exit 2
        ;;
    esac
    ;;
enable)
    if [[ "$OUTPUT_HDR_STATE" == "disabled" ]]; then
        hdr_enable
    else
        echo "$OUTPUT: HDR is already enabled."
    fi
    ;;
disable)
    if [[ "$OUTPUT_HDR_STATE" == "enabled" ]]; then
        hdr_disable
    else
        echo "$OUTPUT: HDR is already disabled."
    fi
    ;;
*)
    printf "Unknown command: %s\n\n" "$TOGGLE"
    show_usage
    exit 2
    ;;
esac

exit 0
