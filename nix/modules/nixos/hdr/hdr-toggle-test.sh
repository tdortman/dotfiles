#!/usr/bin/env bash
# Regression tests for hdr-toggle.sh: HDR must follow the Plasma primary
# output (kscreenctl "primary"), never a hardcoded connector.
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
  cat >"$TMP/bin/kscreenctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "list-outputs --json" ]]; then
  [[ "${KSCREEN_J_FAIL:-0}" == "1" ]] && { echo "kscreenctl: backend gone" >&2; exit 1; }
  cat "$KSCREEN_JSON"
  exit 0
fi
echo "$*" >>"$KSCREEN_CALLS"
[[ -n "${KSCREEN_SET_ERR:-}" ]] && echo "$KSCREEN_SET_ERR" >&2
exit "${KSCREEN_SET_EXIT:-0}"
EOF
  chmod +x "$TMP/bin/kscreenctl"
  export PATH="$TMP/bin:$BASE_PATH"
}
BASE_PATH="$PATH"

fixture() { printf '%s' "$1" >"$TMP/snap.json"; : >"$CALLS"; unset KSCREEN_J_FAIL KSCREEN_SET_EXIT KSCREEN_SET_ERR || true; }

# run <XDG_CURRENT_DESKTOP or - to unset> <args...>
run() {
  local sess="$1"; shift
  : >"$CALLS"
  set +e
  if [[ "$sess" == "-" ]]; then
    OUT=$(env -u XDG_CURRENT_DESKTOP KSCREEN_JSON="$TMP/snap.json" KSCREEN_CALLS="$CALLS" bash -e -u "$TMP/hdr-toggle" "$@" 2>&1)
  else
    OUT=$(env -u DESKTOP_SESSION XDG_CURRENT_DESKTOP="$sess" KSCREEN_JSON="$TMP/snap.json" KSCREEN_CALLS="$CALLS" bash -e -u "$TMP/hdr-toggle" "$@" 2>&1)
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

INTEL_PRIMARY='[{"name":"eDP-1","connected":true,"enabled":true,"primary":true,"capabilities":["hdr","wcg"],"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":true,"primary":false,"capabilities":["hdr","wcg"],"hdr":false}]'
NVIDIA_PRIMARY='[{"name":"eDP-1","connected":true,"enabled":true,"primary":false,"capabilities":["hdr","wcg"],"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":true,"primary":true,"capabilities":["hdr","wcg"],"hdr":true}]'
NO_PRIMARY='[{"name":"eDP-1","connected":true,"enabled":true,"primary":false,"capabilities":["hdr","wcg"],"hdr":false},{"name":"HDMI-A-1","connected":true,"enabled":false,"primary":true,"capabilities":["hdr","wcg"],"hdr":true}]'
INCAPABLE_PRIMARY='[{"name":"eDP-1","connected":true,"enabled":true,"primary":true,"capabilities":["wcg"],"hdr":false}]'
SECONDARY_HDR_ON='[{"name":"eDP-1","connected":true,"enabled":true,"primary":false,"capabilities":["hdr","wcg"],"hdr":true},{"name":"HDMI-A-1","connected":true,"enabled":true,"primary":true,"capabilities":["hdr","wcg"],"hdr":true}]'

render "" ""
fixture "$INTEL_PRIMARY"; run KDE enable
check "enable follows Intel primary" 0 "" "eDP-1 set-hdr-and-wcg true"
fixture "$NVIDIA_PRIMARY"; run KDE disable
check "disable follows NVIDIA primary after switch" 0 "" "HDMI-A-1 set-hdr-and-wcg false"
fixture "$INTEL_PRIMARY"; run KDE enable HDMI-A-1
check "explicit CLI output beats primary" 0 "" "HDMI-A-1 set-hdr-and-wcg true"
fixture "$NO_PRIMARY"; run KDE enable eDP-1
check "explicit output needs no primary" 0 "" "eDP-1 set-hdr-and-wcg true"
fixture "$NO_PRIMARY"; run KDE enable
check "absent or disabled primary fails, no fallback" 1 "" "!calls"
fixture "$INCAPABLE_PRIMARY"; run KDE enable
check "HDR-incapable primary refused" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; run KDE enable NOPE-1
check "unknown output refused" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; KSCREEN_J_FAIL=1 run KDE enable
check "kscreenctl list failure surfaces" 1 "kscreenctl" "!calls"
fixture "$INTEL_PRIMARY"; KSCREEN_SET_EXIT=3 KSCREEN_SET_ERR="kscreenctl: backend exploded" run KDE enable
check "set failure propagates with stderr" 3 "backend exploded" "eDP-1 set-hdr-and-wcg true"
fixture "$NVIDIA_PRIMARY"; run KDE disable HDMI-A-1 /custom.icc
check "explicit ICC honored" 0 "" "HDMI-A-1 set-icc-profile /custom.icc"
fixture "$NVIDIA_PRIMARY"; KSCREEN_SET_EXIT=3 run KDE disable HDMI-A-1 /custom.icc
check "failed HDR disable skips ICC" 3 "" "!set-icc-profile"
run - help
check "help works outside desktop" 0 "Usage:" "!calls"
fixture "$INTEL_PRIMARY"; run GNOME enable
check "non-plasma session refused" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; run KDEX:GNOME enable
check "KDE prefix is not KDE" 1 "" "!calls"
fixture "$INTEL_PRIMARY"; run X-Generic:KDE enable
check "KDE anywhere in desktop list accepted" 0 "" "eDP-1 set-hdr-and-wcg true"

render "" "/def.icc"
fixture "$NVIDIA_PRIMARY"; run KDE disable
check "default ICC applies to resolved default" 0 "" "HDMI-A-1 set-icc-profile /def.icc"
fixture "$SECONDARY_HDR_ON"; run KDE disable HDMI-A-1
check "explicit CLI matching primary gets default ICC" 0 "" "HDMI-A-1 set-icc-profile /def.icc"
fixture "$SECONDARY_HDR_ON"; run KDE disable eDP-1
check "default ICC kept off explicit output" 0 "" "!set-icc-profile"

render "eDP-1" "/def.icc"
fixture "$SECONDARY_HDR_ON"; run KDE disable eDP-1
check "explicit CLI matching config default gets default ICC" 0 "" "eDP-1 set-icc-profile /def.icc"

render "HDMI-A-1" ""
fixture "$INTEL_PRIMARY"; run KDE enable
check "explicit config default honored" 0 "" "HDMI-A-1 set-hdr-and-wcg true"


exit "$FAIL"
