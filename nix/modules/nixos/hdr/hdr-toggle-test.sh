#!/usr/bin/env bash
# Regression tests for hdr-toggle.sh: HDR must follow the Plasma primary
# output (kscreen-doctor priority == 1), never a hardcoded connector.
# Needs only bash + jq. Run:  bash nix/modules/nixos/hdr/hdr-toggle-test.sh
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="${HDR_TOGGLE_UNDER_TEST:-$HERE/hdr-toggle.sh}"
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS="$TMP/calls"
FAIL=0

# render <defaultOutput> <defaultIcc>: substitute config like default.nix does
render() {
  sed -e "s|@defaultOutput@|$1|g" -e "s|@defaultIccProfile@|$2|g" "$SCRIPT" >"$TMP/hdr-toggle"
  chmod +x "$TMP/hdr-toggle"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/kscreen-doctor" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-j" ]]; then
  [[ "${KSCREEN_J_FAIL:-0}" == "1" ]] && { echo "kscreen-doctor: backend gone" >&2; exit 1; }
  cat "$KSCREEN_JSON"
  exit 0
fi
echo "$*" >>"$KSCREEN_CALLS"
[[ -n "${KSCREEN_SET_ERR:-}" ]] && echo "$KSCREEN_SET_ERR" >&2
exit "${KSCREEN_SET_EXIT:-0}"
EOF
  chmod +x "$TMP/bin/kscreen-doctor"
  export PATH="$TMP/bin:$BASE_PATH"
}
BASE_PATH="$PATH"

fixture() { printf '%s' "$1" >"$TMP/snap.json"; : >"$CALLS"; unset KSCREEN_J_FAIL KSCREEN_SET_EXIT KSCREEN_SET_ERR || true; }

# run <DESKTOP_SESSION or - to unset> <args...>
run() {
  local sess="$1"; shift
  : >"$CALLS"
  set +e
  if [[ "$sess" == "-" ]]; then
    OUT=$(env -u DESKTOP_SESSION KSCREEN_JSON="$TMP/snap.json" KSCREEN_CALLS="$CALLS" bash -e -u "$TMP/hdr-toggle" "$@" 2>&1)
  else
    OUT=$(DESKTOP_SESSION="$sess" KSCREEN_JSON="$TMP/snap.json" KSCREEN_CALLS="$CALLS" bash -e -u "$TMP/hdr-toggle" "$@" 2>&1)
  fi
  RC=$?
  set -e
}

check() { # <name> <rc-want> <out-needle> <calls-needle|!calls-needle|!calls>
  local name="$1" rc="$2" needle="$3" calls="$4" ok=1
  [[ "$RC" == "$rc" ]] || ok=0
  [[ -z "$needle" ]] || grep -Fq "$needle" <<<"$OUT" || ok=0
  case "$calls" in
    "!calls") [[ -s "$CALLS" ]] && ok=0 ;;
    "!"*) grep -Fq "${calls:1}" "$CALLS" && ok=0 ;;
    *) grep -Fq "$calls" "$CALLS" || ok=0 ;;
  esac
  if [[ "$ok" == "1" ]]; then echo "ok: $name"; else echo "FAIL: $name (rc=$RC out='$OUT' calls='$(tr '\n' ';' <"$CALLS")')"; FAIL=1; fi
}

INTEL_PRIMARY='{"outputs":[{"name":"eDP-1","connected":true,"enabled":true,"priority":1,"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":true,"priority":2,"hdr":false}]}'
NVIDIA_PRIMARY='{"outputs":[{"name":"eDP-1","connected":true,"enabled":true,"priority":2,"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":true,"priority":1,"hdr":true}]}'
NO_PRIMARY='{"outputs":[{"name":"eDP-1","connected":true,"enabled":true,"priority":2,"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":true,"priority":0,"hdr":true}]}'
INCAPABLE_PRIMARY='{"outputs":[{"name":"eDP-1","connected":true,"enabled":true,"priority":1}]}'
SECONDARY_HDR_ON='{"outputs":[{"name":"eDP-1","connected":true,"enabled":true,"priority":2,"hdr":true},{"name":"HDMI-A-1","connected":true,"enabled":true,"priority":1,"hdr":true}]}'

render "" ""
fixture "$INTEL_PRIMARY"; run plasma enable
check "enable follows Intel primary" 0 "" "output.eDP-1.hdr.enable"
fixture "$NVIDIA_PRIMARY"; run plasma disable
check "disable follows NVIDIA primary after switch" 0 "" "output.HDMI-A-1.hdr.disable"
fixture "$INTEL_PRIMARY"; run plasma enable HDMI-A-1
check "explicit CLI output beats primary" 0 "" "output.HDMI-A-1.hdr.enable"
fixture "$NO_PRIMARY"; run plasma enable eDP-1
check "explicit output needs no primary" 0 "" "output.eDP-1.hdr.enable"
fixture "$NO_PRIMARY"; run plasma enable
check "absent primary fails, no fallback" 1 "" "!calls"
fixture "$INCAPABLE_PRIMARY"; run plasma enable
check "HDR-incapable primary refused" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; run plasma enable NOPE-1
check "unknown output refused" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; KSCREEN_J_FAIL=1 run plasma enable
check "kscreen -j failure surfaces" 1 "kscreen-doctor" "!calls"
fixture "$INTEL_PRIMARY"; KSCREEN_SET_EXIT=3 KSCREEN_SET_ERR="kscreen-doctor: backend exploded" run plasma enable
check "set failure propagates with stderr" 3 "backend exploded" "output.eDP-1.hdr.enable"
fixture "$NVIDIA_PRIMARY"; run plasma disable HDMI-A-1 /custom.icc
check "explicit ICC honored" 0 "" "output.HDMI-A-1.iccprofile./custom.icc"
run - help
check "help works outside desktop" 0 "Usage:" "!calls"
fixture "$INTEL_PRIMARY"; run x11 enable
check "non-plasma session refused" 1 "" "!calls"

render "" "/def.icc"
fixture "$NVIDIA_PRIMARY"; run plasma disable
check "default ICC applies to resolved default" 0 "" "output.HDMI-A-1.iccprofile./def.icc"
fixture "$SECONDARY_HDR_ON"; run plasma disable HDMI-A-1
check "explicit CLI matching primary gets default ICC" 0 "" "output.HDMI-A-1.iccprofile./def.icc"
fixture "$SECONDARY_HDR_ON"; run plasma disable eDP-1
check "default ICC kept off explicit output" 0 "" "!iccprofile"

render "eDP-1" "/def.icc"
fixture "$SECONDARY_HDR_ON"; run plasma disable eDP-1
check "explicit CLI matching config default gets default ICC" 0 "" "output.eDP-1.iccprofile./def.icc"

render "HDMI-A-1" ""
fixture "$INTEL_PRIMARY"; run plasma enable
check "explicit config default honored" 0 "" "output.HDMI-A-1.hdr.enable"


exit "$FAIL"
