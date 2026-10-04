{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.tern;

  # Tern itself is installed system-wide, so `tern` resolves via the user PATH.
  tern-focus = pkgs.writeShellApplication {
    name = "tern-focus";
    runtimeInputs = [ pkgs.kdotool ];

    text = ''
      window=$(kdotool search --limit 1 --class '^so\.stencil\.tern$')

      if [[ -n $window ]]; then
        exec kdotool windowactivate "$window"
      fi

      exec tern
    '';
  };
in
{
  options.custom.tern.enable = lib.mkEnableOption "Meta+Return hotkey that focuses Tern, launching it if no window exists";

  config = lib.mkIf cfg.enable {
    programs.plasma.hotkeys.commands.tern-focus = {
      command = lib.getExe tern-focus;
      comment = "Focus Tern, or launch it if it isn't running";
      key = "Meta+Return";
      name = "Focus or launch Tern";
    };
  };
}
