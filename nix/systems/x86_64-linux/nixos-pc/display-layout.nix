{ lib, pkgs, ... }:

let
  displayLayout = pkgs.writeShellApplication {
    name = "display-layout";

    runtimeInputs = [
      pkgs.jq
      pkgs.kdePackages.libkscreen
    ];

    text = ''
      usage() {
        printf '%s\n' "Usage: display-layout [intel|nvidia]" "" "Apply the declarative output layout with kscreen-doctor." "  intel   DP-1 left primary + DP-2 right (default)" "  nvidia  HDMI-A-5 primary + DP-2 right" "" "The outputs share a bottom edge using their current scales." "The unused alternate main and DP-4 are disabled when present." "DP-2 is optional and skipped when disconnected." "Existing mode, scale, refresh rate, and HDR settings are preserved."
      }

      if [ $# -gt 1 ]; then
        echo "display-layout: expected at most one argument" >&2
        usage >&2
        exit 2
      fi

      mode=intel
      if [ $# -eq 1 ]; then
        mode=$1
      fi

      # Help works without a desktop session; invalid modes fail before
      # talking to the compositor.
      case "$mode" in
        -h | --help | help)
          usage
          exit 0
          ;;
        intel | nvidia) ;;
        *)
          echo "display-layout: unknown layout '$mode' (expected intel|nvidia)" >&2
          usage >&2
          exit 2
          ;;
      esac

      MAIN=DP-1
      ALT=HDMI-A-5
      if [ "$mode" = nvidia ]; then
        MAIN=HDMI-A-5
        ALT=DP-1
      fi
      SEC=DP-2
      SPARE=DP-4

      # Single compositor snapshot; every decision below reuses it.
      if ! SNAP=$(kscreen-doctor -j); then
        echo "display-layout: kscreen-doctor -j failed, cannot read output state." >&2
        exit 1
      fi

      if ! MAIN_CONNECTED=$(jq -r --arg m "$MAIN" '[.outputs[] | select(.name == $m and .connected == true)] | length > 0' <<<"$SNAP"); then
        echo "display-layout: failed to parse kscreen-doctor output." >&2
        exit 1
      fi
      if [ "$MAIN_CONNECTED" != true ]; then
        echo "display-layout: main output '$MAIN' not connected, cannot apply $mode layout. See 'kscreen-doctor -o'." >&2
        exit 1
      fi

      if ! SEC_CONNECTED=$(jq -r --arg m "$SEC" '[.outputs[] | select(.name == $m and .connected == true)] | length > 0' <<<"$SNAP"); then
        echo "display-layout: failed to parse kscreen-doctor output." >&2
        exit 1
      fi

      # Positions use scaled dimensions, with a shared bottom edge. Disabled
      # outputs can report size 0x0, so use their selected mode in that case.
      X=0
      MAIN_Y=0
      SEC_Y=0
      if [ "$SEC_CONNECTED" = true ]; then
        if ! POSITIONS=$(jq -er --arg m "$MAIN" --arg s "$SEC" '
          def logical_size:
            . as $o
            | (.scale | if type != "number" or . <= 0 then error("invalid output scale") else . end) as $scale
            | (if (.size.width // 0) > 0 and (.size.height // 0) > 0 then .size
               else (.currentModeId | tostring) as $cur
                 | [.modes[]? | select((.id | tostring) == $cur) | .size] | first end) as $size
            | if ($size.width // 0) <= 0 or ($size.height // 0) <= 0
              then error("missing dimensions for " + $o.name)
              else [($size.width / $scale | ceil), ($size.height / $scale | ceil)] end;
          (.outputs[] | select(.name == $m) | logical_size) as $main
          | (.outputs[] | select(.name == $s) | logical_size) as $secondary
          | [$main[0], ([0, $secondary[1] - $main[1]] | max), ([0, $main[1] - $secondary[1]] | max)]
          | @tsv
        ' <<<"$SNAP"); then
          echo "display-layout: cannot determine scaled output dimensions for bottom alignment." >&2
          exit 1
        fi
        read -r X MAIN_Y SEC_Y <<<"$POSITIONS"
      fi

      ARGS=("output.$MAIN.enable" "output.$MAIN.position.0,$MAIN_Y" "output.$MAIN.priority.1")
      if [ "$SEC_CONNECTED" = true ]; then
        ARGS+=("output.$SEC.enable" "output.$SEC.position.$X,$SEC_Y" "output.$SEC.priority.2")
      fi
      if jq -e --arg n "$ALT" '.outputs | map(.name) | index($n) != null' <<<"$SNAP" >/dev/null; then
        ARGS+=(output."$ALT".disable)
      fi
      if jq -e --arg n "$SPARE" '.outputs | map(.name) | index($n) != null' <<<"$SNAP" >/dev/null; then
        ARGS+=(output."$SPARE".disable)
      fi

      kscreen-doctor "''${ARGS[@]}"

      # kscreen-doctor can exit successfully even when KWin rejects the change.
      if ! kscreen-doctor -j | jq -e \
        --arg main "$MAIN" --arg secondary "$SEC" --arg alt "$ALT" --arg spare "$SPARE" \
        --argjson secondaryConnected "$SEC_CONNECTED" --argjson x "$X" \
        --argjson mainY "$MAIN_Y" --argjson secondaryY "$SEC_Y" '
          (.outputs | map({key: .name, value: .}) | from_entries) as $outputs
          | ($outputs[$main].enabled == true
            and $outputs[$main].priority == 1
            and $outputs[$main].pos == {x: 0, y: $mainY}
            and ($secondaryConnected | not
              or ($outputs[$secondary].enabled == true
                and $outputs[$secondary].priority == 2
                and $outputs[$secondary].pos == {x: $x, y: $secondaryY}))
            and ($outputs[$alt].enabled != true)
            and ($outputs[$spare].enabled != true))
        ' >/dev/null; then
        echo "display-layout: compositor did not apply the requested layout; check that this display session is active." >&2
        exit 1
      fi
    '';
  };
in
{
  environment.systemPackages = [ displayLayout ];
  system.build.displayLayout = displayLayout;

  systemd.user.services.plasma-login-layout = {
    description = "Apply declarative Intel display layout at Plasma login";
    before = [ "plasma-login.service" ];
    after = [ "plasma-login-kwin_wayland.service" ];
    wantedBy = [ "plasma-login-wayland.target" ];
    partOf = [ "plasma-login-wayland.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe displayLayout} intel";
    };
  };
}
