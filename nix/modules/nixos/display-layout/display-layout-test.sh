#!/usr/bin/env bash
# Behavioral tests for generalized full display-layouts.
# Layouts carry full output lists (priority 1 = primary flag, others 2..N in
# list order); auto row bottom-aligned, explicit position overrides. All
# listed outputs are required: a disconnected output fails before mutation.
# Cycle compares whole managed state with login fallback; managed-absent
# disabled when present, unmanaged untouched.
# DDC stays disabled here (hardware-verified separately);
# kscreen-doctor/ddcutil are faked via namespace bind over store paths and
# /sys is a fixture bind, so the real generated binary runs unmodified. No
# host GPU dependence. Needs bash + jq + nix (+ unshare userns for runtime half).
# Run: bash nix/modules/nixos/display-layout/display-layout-test.sh
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || { cd -- "$HERE/../../../.." && pwd; })
MODULE="$ROOT/nix/modules/nixos/display-layout/default.nix"
[[ -f "$MODULE" ]] || { echo "SKIP: module not found: $MODULE"; exit 2; }
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 2; }
command -v nix >/dev/null || { echo "SKIP: nix not on PATH"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CALLS="$TMP/calls"
COUNT="$TMP/count"
FAIL=0

# mk_frag <file> <display-layout-config-nix>: minimal system evaluating only
# the package output, so invalid configs fail at package build evaluation.
mk_frag() {
  cat >"$1" <<EOF
let flake = builtins.getFlake "git+file://${ROOT}";
in (flake.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    $MODULE
    { display-layout = {
$2
    }; }
  ];
}).config.system.build.displayLayout
EOF
}

MAIN_CFG='
      enable = true;
      loginLayout = "desk";
      ddc.enable = false;
      layouts = [
        {
          name = "desk";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; }
            { gpu = "0000:00:0a.0"; output = "DP-2"; }
          ];
          disabledOutputs = [ "DP-4" ];
        }
        {
          name = "desk-alt";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; }
            { gpu = "0000:00:0a.0"; output = "DP-3"; }
          ];
          disabledOutputs = [ "DP-4" ];
        }
        {
          name = "stage";
          outputs = [
            { gpu = "0000:00:0b.0"; output = "HDMI-A-5"; }
            { gpu = "0000:00:0a.0"; output = "DP-2"; primary = true; }
            { gpu = "0000:00:0a.0"; output = "DP-3"; }
          ];
          disabledOutputs = [ "DP-4" ];
        }
      ];
'

PINNED_CFG='
      enable = true;
      loginLayout = "pinned";
      ddc.enable = false;
      layouts = [
        {
          name = "pinned";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; position = { x = 0; y = 10; }; }
            { gpu = "0000:00:0a.0"; output = "DP-2"; position = { x = 200; y = 30; }; }
          ];
          disabledOutputs = [ ];
        }
      ];
'
SCALED_CFG='
      enable = true;
      loginLayout = "lo";
      ddc.enable = false;
      layouts = [
        {
          name = "lo";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; scale = 1; }
            { gpu = "0000:00:0a.0"; output = "DP-2"; }
          ];
          disabledOutputs = [ ];
        }
        {
          name = "hi";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; scale = 2; }
            { gpu = "0000:00:0a.0"; output = "DP-2"; }
          ];
          disabledOutputs = [ ];
        }
      ];
'

SOLO_CFG='
      enable = true;
      loginLayout = "s1";
      ddc.enable = false;
      layouts = [
        {
          name = "s1";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; scale = 1; }
          ];
          disabledOutputs = [ ];
        }
        {
          name = "s2";
          outputs = [
            { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; scale = 2; }
          ];
          disabledOutputs = [ ];
        }
      ];
'

mk_frag "$TMP/main.nix" "$MAIN_CFG"
mk_frag "$TMP/pinned.nix" "$PINNED_CFG"
mk_frag "$TMP/scaled.nix" "$SCALED_CFG"
mk_frag "$TMP/solo.nix" "$SOLO_CFG"

BIN_MAIN=""
BIN_PINNED=""
BIN_SCALED=""
BIN_SOLO=""
if ! OUT_MAIN=$(nix build --impure --no-link --print-out-paths -f "$TMP/main.nix" 2>"$TMP/main-build.err" | tail -n 1); then
  echo "FAIL: main config did not build (generalized schema?): $(head -c 300 "$TMP/main-build.err")"
  FAIL=1
else
  BIN_MAIN="$OUT_MAIN/bin/display-layout"
fi
if ! OUT_PINNED=$(nix build --impure --no-link --print-out-paths -f "$TMP/pinned.nix" 2>"$TMP/pinned-build.err" | tail -n 1); then
  echo "FAIL: pinned config did not build: $(head -c 300 "$TMP/pinned-build.err")"
  FAIL=1
else
  BIN_PINNED="$OUT_PINNED/bin/display-layout"
fi
if ! OUT_SCALED=$(nix build --impure --no-link --print-out-paths -f "$TMP/scaled.nix" 2>"$TMP/scaled-build.err" | tail -n 1); then
  echo "FAIL: scaled config did not build: $(head -c 300 "$TMP/scaled-build.err")"
  FAIL=1
else
  BIN_SCALED="$OUT_SCALED/bin/display-layout"
fi
if ! OUT_SOLO=$(nix build --impure --no-link --print-out-paths -f "$TMP/solo.nix" 2>"$TMP/solo-build.err" | tail -n 1); then
  echo "FAIL: solo config did not build: $(head -c 300 "$TMP/solo-build.err")"
  FAIL=1
else
  BIN_SOLO="$OUT_SOLO/bin/display-layout"
fi
[[ -n "$BIN_MAIN" && -f "$BIN_MAIN" ]] || BIN_MAIN=""
[[ -n "$BIN_PINNED" && -f "$BIN_PINNED" ]] || BIN_PINNED=""
[[ -n "$BIN_SCALED" && -f "$BIN_SCALED" ]] || BIN_SCALED=""
[[ -n "$BIN_SOLO" && -f "$BIN_SOLO" ]] || BIN_SOLO=""
ACTIVE_BIN="$BIN_MAIN"

# collect_targets <bin> <name>: store files for <name> referenced by <bin>
# plus the canonical flake path, one per line. Best effort, never fails.
collect_targets() {
  local bin="$1" name="$2" d canon=""
  [[ -n "$bin" && -f "$bin" ]] || return 0
  grep -o '/nix/store/[a-z0-9][a-z0-9._-]*/bin' "$bin" 2>/dev/null | sort -u | while read -r d; do
    if [[ -e "$d/$name" ]]; then printf '%s\n' "$d/$name"; fi
  done || true
  if [[ "$name" == "kscreen-doctor" ]]; then
    canon=$(nix eval --impure --raw --expr "(builtins.getFlake \"git+file://${ROOT}\").inputs.nixpkgs.legacyPackages.x86_64-linux.kdePackages.libkscreen + \"/bin/kscreen-doctor\"" 2>/dev/null || true)
  elif [[ "$name" == "ddcutil" ]]; then
    canon=$(nix eval --impure --raw --expr "(builtins.getFlake \"git+file://${ROOT}\").inputs.nixpkgs.legacyPackages.x86_64-linux.ddcutil + \"/bin/ddcutil\"" 2>/dev/null || true)
  fi
  if [[ -n "$canon" && -e "$canon" ]]; then printf '%s\n' "$canon"; fi
  return 0
}

KS_TARGETS=$( { [[ -n "$BIN_MAIN" ]] && collect_targets "$BIN_MAIN" kscreen-doctor; [[ -n "$BIN_PINNED" ]] && collect_targets "$BIN_PINNED" kscreen-doctor; [[ -n "$BIN_SCALED" ]] && collect_targets "$BIN_SCALED" kscreen-doctor; [[ -n "$BIN_SOLO" ]] && collect_targets "$BIN_SOLO" kscreen-doctor; } | sort -u || true)
DDC_TARGETS=$( { [[ -n "$BIN_MAIN" ]] && collect_targets "$BIN_MAIN" ddcutil; [[ -n "$BIN_PINNED" ]] && collect_targets "$BIN_PINNED" ddcutil; [[ -n "$BIN_SCALED" ]] && collect_targets "$BIN_SCALED" ddcutil; [[ -n "$BIN_SOLO" ]] && collect_targets "$BIN_SOLO" ddcutil; } | sort -u || true)

setup_fakes() {
  mkdir -p "$TMP/bin"
  cat >"$TMP/fake-kscreen" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-j" ]]; then
  c=$(cat "$KSCREEN_COUNT" 2>/dev/null || echo 0)
  if [[ "$c" == "0" ]]; then cat "$KSCREEN_PRE"; else cat "$KSCREEN_POST"; fi
  echo $((c + 1)) >"$KSCREEN_COUNT"
  exit 0
fi
echo "kscreen-doctor $*" >>"$KSCREEN_CALLS"
exit "${KSCREEN_SET_EXIT:-0}"
EOF
  chmod +x "$TMP/fake-kscreen"
  cat >"$TMP/fake-ddcutil" <<'EOF'
#!/usr/bin/env bash
echo "ddcutil $*" >>"$KSCREEN_CALLS"
exit "${DDC_EXIT:-0}"
EOF
  chmod +x "$TMP/fake-ddcutil"
  FAKESYS="$TMP/fakesys"
  rm -rf "$FAKESYS"
  mkdir -p "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-1" \
    "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-2" \
    "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-3" \
    "$FAKESYS/bus/pci/devices/0000:00:0b.0/drm/card1/card1-HDMI-A-5"
  cat >"$TMP/ns-run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mount --bind "$FAKESYS" /sys || { echo "test-harness: cannot bind fake /sys" >&2; exit 99; }
if [[ -n "${KS_TARGETS:-}" ]]; then
  while IFS= read -r t; do
    [[ -n "$t" && -e "$t" ]] || continue
    mount --bind "$FAKE_KS" "$t" || { echo "test-harness: cannot bind fake kscreen-doctor over $t" >&2; exit 99; }
  done <<<"$KS_TARGETS"
fi
if [[ -n "${DDC_TARGETS:-}" ]]; then
  while IFS= read -r t; do
    [[ -n "$t" && -e "$t" ]] || continue
    mount --bind "$FAKE_DDC" "$t" || true
  done <<<"$DDC_TARGETS"
fi
exec "$ACTIVE_BIN" "$@"
EOF
  chmod +x "$TMP/ns-run.sh"
}

probe_ns() { # mount-namespace probe gating the fake-/sys + store-bind runtime half
  NS_OK=0
  if command -v unshare >/dev/null; then
    local probe_target=""
    probe_target=$(head -n 1 <<<"$KS_TARGETS" || true)
    if [[ -z "$probe_target" ]]; then
      if FAKESYS="$FAKESYS" unshare --user --map-root-user --mount --propagation private bash -c 'mount --bind "$FAKESYS" /sys && test -d /sys/bus/pci/devices' 2>/dev/null; then
        NS_OK=1
      fi
    else
      if FAKESYS="$FAKESYS" FAKE_KS="$TMP/fake-kscreen" REAL_KS="$probe_target" unshare --user --map-root-user --mount --propagation private bash -c 'mount --bind "$FAKESYS" /sys && mount --bind "$FAKE_KS" "$REAL_KS" && test -d /sys/bus/pci/devices' 2>/dev/null; then
        NS_OK=1
      fi
    fi
  fi
}

# fixture <pre-json> <post-json>: reset boundary state
fixture() {
  printf '%s' "$1" >"$TMP/pre.json"
  printf '%s' "$2" >"$TMP/post.json"
  echo 0 >"$COUNT"
  : >"$CALLS"
  unset KSCREEN_SET_EXIT DDC_EXIT || true
}

# run <args...>: exec ACTIVE_BIN in namespace with fakes
run() {
  : >"$CALLS"
  echo 0 >"$COUNT"
  set +e
  OUT=$(FAKESYS="$FAKESYS" FAKE_KS="$TMP/fake-kscreen" FAKE_DDC="$TMP/fake-ddcutil" KS_TARGETS="$KS_TARGETS" DDC_TARGETS="$DDC_TARGETS" ACTIVE_BIN="$ACTIVE_BIN" KSCREEN_PRE="$TMP/pre.json" KSCREEN_POST="$TMP/post.json" KSCREEN_COUNT="$COUNT" KSCREEN_CALLS="$CALLS" unshare --user --map-root-user --mount --propagation private bash "$TMP/ns-run.sh" "$@" 2>&1)
  RC=$?
  set -e
}

check() { # <name> <rc-want> <out-needle|!empty> <calls-needle|!calls-needle|!calls>
  local name="$1" rc="$2" needle="$3" calls="$4" ok=1
  [[ "$RC" == "$rc" ]] || ok=0
  if [[ "$needle" == "!empty" ]]; then [[ -n "$OUT" ]] || ok=0
  elif [[ -n "$needle" ]]; then grep -Fq "$needle" <<<"$OUT" || ok=0; fi
  case "$calls" in
    "!calls") [[ -s "$CALLS" ]] && ok=0 ;;
    "!"*) grep -Fq "${calls:1}" "$CALLS" && ok=0 ;;
    *) grep -Fq "$calls" "$CALLS" || ok=0 ;;
  esac
  if [[ "$ok" == "1" ]]; then echo "ok: $name"; else echo "FAIL: $name (rc=$RC out='$OUT' calls='$(tr '\n' ';' <"$CALLS")')"; FAIL=1; fi
}

expect_fail() { # <name> <frag>: package build evaluation must reject config
  local name="$1" frag="$2" rc=0 err=""
  set +e
  err=$(nix build --impure --no-link -f "$frag" 2>&1 >/dev/null)
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]] && grep -Fq "display-layout" <<<"$err"; then echo "ok: $name";
  else echo "FAIL: $name (rc=$rc err='$(head -c 300 <<<"$err")')"; FAIL=1; fi
}

mk_out() { # <name> <connected> <enabled> <priority> <posx> <posy> <w> <h> [scale]
  local scale="${9:-1}"
  printf '{"name":"%s","connected":%s,"enabled":%s,"priority":%s,"pos":{"x":%s,"y":%s},"size":{"width":%s,"height":%s},"scale":%s,"currentModeId":1,"modes":[{"id":1,"size":{"width":%s,"height":%s}}]}' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$scale" "$7" "$8"
}

snap() { printf '{"outputs":[%s]}' "$1"; }

# Sizes: DP-1 100x100, DP-2 100x200 tall, DP-3 100x50 short, HDMI 120x80.
# Desk: DP-1(0,100,p1)+DP-2(100,0,p2) maxH200.
DP1_DESK=$(mk_out DP-1 true true 1 0 100 100 100)
DP2_DESK=$(mk_out DP-2 true true 2 100 0 100 200)
DP3_DIS=$(mk_out DP-3 true false 0 0 0 100 50)
HDMI_DIS=$(mk_out HDMI-A-5 true false 0 0 0 120 80)
SPARE_DIS=$(mk_out DP-4 false false 0 0 0 100 100)
UNMANAGED=$(mk_out DP-9 true true 4 500 0 100 100)
PRE_DESK=$(snap "$DP1_DESK,$DP2_DESK,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")

# Desk-alt: DP-1(0,0,p1)+DP-3(100,50,p2) maxH100.
DP1_ALT=$(mk_out DP-1 true true 1 0 0 100 100)
DP2_DIS=$(mk_out DP-2 true false 0 0 0 100 200)
DP3_ALT=$(mk_out DP-3 true true 2 100 50 100 50)
PRE_ALT=$(snap "$DP1_ALT,$DP2_DIS,$DP3_ALT,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")

# Stage 3-monitor middle primary: HDMI(0,120,p2)+DP-2(120,0,p1)+DP-3(220,150,p3) maxH200.
HDMI_STAGE=$(mk_out HDMI-A-5 true true 2 0 120 120 80)
DP2_STAGE=$(mk_out DP-2 true true 1 120 0 100 200)
DP3_STAGE=$(mk_out DP-3 true true 3 220 150 100 50)
DP1_DIS=$(mk_out DP-1 true false 0 0 0 100 100)
PRE_STAGE=$(snap "$DP1_DIS,$DP2_STAGE,$DP3_STAGE,$HDMI_STAGE,$SPARE_DIS,$UNMANAGED")
# Stage HDMI-missing postcondition: HDMI gone, DP-2(0,0,p1)+DP-3(100,150,p2) maxH200.
HDMI_MISSING=$(mk_out HDMI-A-5 false false 0 0 0 120 80)
DP2_NOHDMI=$(mk_out DP-2 true true 1 0 0 100 200)
DP3_NOHDMI=$(mk_out DP-3 true true 2 100 150 100 50)
PRE_STAGE_NOHDMI=$(snap "$DP1_DIS,$DP2_NOHDMI,$DP3_NOHDMI,$HDMI_MISSING,$SPARE_DIS,$UNMANAGED")

# Unknown: DP-1 primary but DP-2+DP-3 both enabled matches no layout.
DP3_EXTRA=$(mk_out DP-3 true true 3 200 0 100 50)
PRE_UNKNOWN=$(snap "$DP1_DESK,$DP2_DESK,$DP3_EXTRA,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")

# Non-primary missing: stage with DP-3 disconnected.
DP3_REQMISS=$(mk_out DP-3 false false 0 0 0 100 50)
PRE_STAGE_REQMISS=$(snap "$DP1_DIS,$DP2_STAGE,$DP3_REQMISS,$HDMI_STAGE,$SPARE_DIS,$UNMANAGED")

# Pinned explicit: DP-1(0,10,p1)+DP-2(200,30,p2).
DP1_PIN=$(mk_out DP-1 true true 1 0 10 100 100)
DP2_PIN=$(mk_out DP-2 true true 2 200 30 100 200)
PRE_PINNED_POST=$(snap "$DP1_PIN,$DP2_PIN,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")
# Scaled hi: DP-1 at scale 2 is logically 50x50, so the row bottom-aligns at
# maxH 200 as DP-1(0,150,p1,s2)+DP-2(50,0,p2,s1). Lo matches desk geometry.
DP1_HI=$(mk_out DP-1 true true 1 0 150 100 100 2)
DP2_HI=$(mk_out DP-2 true true 2 50 0 100 200)
PRE_HI=$(snap "$DP1_HI,$DP2_HI,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")
# Compositor ignored the scale change: hi positions but DP-1 still at scale 1.
DP1_HI_IGNORED=$(mk_out DP-1 true true 1 0 150 100 100)
PRE_HI_IGNORED=$(snap "$DP1_HI_IGNORED,$DP2_HI,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")
# Solo single-output layouts differ only in scale: geometry is (0,0,p1) either way.
DP1_S2=$(mk_out DP-1 true true 1 0 0 100 100 2)
PRE_S1=$(snap "$DP1_ALT,$DP2_DIS,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")
PRE_S2=$(snap "$DP1_S2,$DP2_DIS,$DP3_DIS,$HDMI_DIS,$SPARE_DIS,$UNMANAGED")

setup_fakes

probe_ns

if [[ "$NS_OK" == "1" && -n "$BIN_MAIN" ]]; then
ACTIVE_BIN="$BIN_MAIN"
fixture "$PRE_DESK" "$PRE_STAGE"; run stage
check "3-monitor auto bottom alignment applies" 0 "" "output.HDMI-A-5.enable"
check "3-monitor leftmost position" 0 "" "output.HDMI-A-5.position.0,120"
check "3-monitor leftmost priority 2" 0 "" "output.HDMI-A-5.priority.2"
check "3-monitor middle primary position" 0 "" "output.DP-2.position.120,0"
check "3-monitor middle primary priority 1" 0 "" "output.DP-2.priority.1"
check "3-monitor third position" 0 "" "output.DP-3.position.220,150"
check "3-monitor third priority" 0 "" "output.DP-3.priority.3"
check "3-monitor disables managed absent" 0 "" "output.DP-1.disable"
check "3-monitor disables configured output" 0 "" "output.DP-4.disable"
check "3-monitor leaves unmanaged untouched" 0 "" "!DP-9"
check "unscaled layout sends no scale args" 0 "" "!scale."

fixture "$PRE_DESK" "$PRE_ALT"; run
check "same-primary cycle desk to desk-alt" 0 "" "output.DP-3.enable"
check "same-primary disables other secondary" 0 "" "output.DP-2.disable"
check "same-primary alt position" 0 "" "output.DP-3.position.100,50"
check "same-primary alt priority" 0 "" "output.DP-3.priority.2"

fixture "$PRE_ALT" "$PRE_STAGE"; run cycle
check "cycle desk-alt to stage" 0 "" "output.HDMI-A-5.enable"

fixture "$PRE_STAGE" "$PRE_DESK"; run cycle
check "3 profile wrap stage to desk" 0 "" "output.DP-1.enable"
check "wrap disables stage primary" 0 "" "!output.HDMI-A-5.enable"
check "wrap disables stage primary via disable" 0 "" "output.HDMI-A-5.disable"

fixture "$PRE_UNKNOWN" "$PRE_DESK"; run
check "unknown whole state falls back to login" 0 "" "output.DP-1.enable"
check "fallback disables extra managed" 0 "" "output.DP-3.disable"

fixture "$PRE_STAGE_REQMISS" "$PRE_STAGE_REQMISS"; run stage
check "non-primary disconnected fails before mutation" 1 "!empty" "!calls"
fixture "$PRE_STAGE" "$PRE_STAGE_NOHDMI"; run stage
check "required output disappearing mid-apply rejected" 1 "!empty" "output.HDMI-A-5.enable"

mv "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-1" "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-1.hidden"
fixture "$PRE_DESK" "$PRE_ALT"; run desk-alt
check "wrong gpu refused before mutation" 1 "!empty" "!calls"
mv "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-1.hidden" "$FAKESYS/bus/pci/devices/0000:00:0a.0/drm/card0/card0-DP-1"

fixture "$PRE_DESK" "$PRE_DESK"; run desk-alt
check "compositor rejection fails visibly" 1 "!empty" "output.DP-3.enable"

if [[ -n "$BIN_PINNED" ]]; then
ACTIVE_BIN="$BIN_PINNED"
fixture "$PRE_DESK" "$PRE_PINNED_POST"; run pinned
check "explicit position overrides auto" 0 "" "output.DP-1.position.0,10"
check "explicit second position verbatim" 0 "" "output.DP-2.position.200,30"
check "explicit priorities kept" 0 "" "output.DP-1.priority.1"
check "explicit second priority" 0 "" "output.DP-2.priority.2"
check "explicit leaves unmanaged untouched" 0 "" "!DP-9"
ACTIVE_BIN="$BIN_MAIN"
fi

if [[ -n "$BIN_SCALED" ]]; then
ACTIVE_BIN="$BIN_SCALED"
# Lo matches desk geometry; hi halves DP-1 to logical 50x50.
fixture "$PRE_DESK" "$PRE_HI"; run hi
check "target scale applied in same transaction" 0 "" "output.DP-1.scale.2"
check "scaled primary bottom-aligns on target height" 0 "" "output.DP-1.position.0,150"
check "follower x accumulates scaled width" 0 "" "output.DP-2.position.50,0"

check "unscaled follower sends no scale arg" 0 "" "!output.DP-2.scale."
fixture "$PRE_DESK" "$PRE_HI_IGNORED"; run hi
check "ignored scale change fails postcondition" 1 "!empty" "output.DP-1.scale.2"
fixture "$PRE_HI" "$PRE_DESK"; run cycle
check "cycle wraps scaled hi to lo" 0 "" "output.DP-1.position.0,100"
check "cycle restores layout scale" 0 "" "output.DP-1.scale.1"
ACTIVE_BIN="$BIN_MAIN"
fi

if [[ -n "$BIN_SOLO" ]]; then
ACTIVE_BIN="$BIN_SOLO"
fixture "$PRE_S2" "$PRE_S1"; run cycle
check "cycle distinguishes scale-only layouts" 0 "" "output.DP-1.scale.1"
ACTIVE_BIN="$BIN_MAIN"
fi

else
  if [[ "$NS_OK" != "1" ]]; then
    echo "FAIL: runtime cases need a mount namespace (unshare + userns) for fake /sys and store binds"
    FAIL=1
  fi
  if [[ -z "$BIN_MAIN" ]]; then
    echo "FAIL: runtime cases need main binary (see build failure above)"
    FAIL=1
  fi
fi

mk_frag "$TMP/bad-dup-conn.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; } { gpu = "0000:00:0a.0"; output = "DP-1"; } ]; }
      ];
'
expect_fail "duplicate connector within layout rejected" "$TMP/bad-dup-conn.nix"
mk_frag "$TMP/bad-no-primary.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; } { gpu = "0000:00:0a.0"; output = "DP-2"; } ]; }
      ];
'
expect_fail "primary not set rejected" "$TMP/bad-no-primary.nix"
mk_frag "$TMP/bad-multi-primary.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; } { gpu = "0000:00:0a.0"; output = "DP-2"; primary = true; } ]; }
      ];
'
expect_fail "multiple primaries rejected" "$TMP/bad-multi-primary.nix"
mk_frag "$TMP/bad-collision.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; } ]; disabledOutputs = [ "DP-1" ]; }
      ];
'
expect_fail "enable-disable collision rejected" "$TMP/bad-collision.nix"
mk_frag "$TMP/bad-conn.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "BAD OUTPUT!"; primary = true; } ]; }
      ];
'
expect_fail "malformed connector rejected at package build" "$TMP/bad-conn.nix"
mk_frag "$TMP/bad-gpu.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "nope"; output = "DP-1"; primary = true; } ]; }
      ];
'
expect_fail "malformed gpu rejected at package build" "$TMP/bad-gpu.nix"
mk_frag "$TMP/dup-name.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; } ]; }
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-2"; primary = true; } ]; }
      ];
'
expect_fail "duplicate layout names rejected" "$TMP/dup-name.nix"
mk_frag "$TMP/bad-login.nix" '
      enable = true;
      loginLayout = "ghost";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; } ]; }
      ];
'
expect_fail "missing login layout rejected at package build" "$TMP/bad-login.nix"
mk_frag "$TMP/bad-negpos.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; position = { x = -10; y = 0; }; } ]; }
      ];
'
expect_fail "negative position rejected at package build" "$TMP/bad-negpos.nix"
mk_frag "$TMP/bad-scale.nix" '
      enable = true;
      loginLayout = "a";
      ddc.enable = false;
      layouts = [
        { name = "a"; outputs = [ { gpu = "0000:00:0a.0"; output = "DP-1"; primary = true; scale = 0; } ]; }
      ];
'
expect_fail "non-positive scale rejected at package build" "$TMP/bad-scale.nix"
mk_frag "$TMP/old-globals.nix" '
      enable = true;
      loginLayout = "intel";
      secondaryOutput = "DP-2";
      disabledOutputs = [ "DP-4" ];
      ddc.enable = false;
      ddc.controlLayout = "intel";
      layouts = [
        { name = "intel"; gpu = "0000:00:0a.0"; output = "DP-1"; }
        { name = "nvidia"; gpu = "0000:00:0b.0"; output = "HDMI-A-5"; }
      ];
'
expect_fail "old globals removed" "$TMP/old-globals.nix"

exit "$FAIL"
