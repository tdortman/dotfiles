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
  tern-terminal = pkgs.writeShellApplication {
    name = "tern-terminal";
    runtimeInputs = [ pkgs.kdotool ];

    text = ''
      window=$(kdotool search --limit 1 --class '^so\.stencil\.tern$')
      if [[ -z $window ]]; then
        exec tern "$@"
      fi

      args=(new tab --cwd "$PWD")
      if (( $# )); then
        if [[ $1 != -e || $# -lt 2 ]]; then
          echo "Usage: tern-terminal [-e COMMAND [ARGS...]]" >&2
          exit 2
        fi
        shift
        args+=(-- "$@")
      fi

      # Give the window focus before selecting its new tab.
      kdotool windowactivate "$window"
      block=$(tern "''${args[@]}")
      exec tern focus "$block"
    '';
  };
in
{
  options.custom.tern.enable = lib.mkEnableOption "Tern terminal integration and focus shortcut";

  config = lib.mkIf cfg.enable {
    home.packages = [ tern-terminal ];

    programs.plasma = {
      # KDE launches terminals in the requested directory as the working directory.
      configFile.kdeglobals.General = {
        TerminalApplication = "tern-terminal";
        TerminalService = "tern-terminal.desktop";
      };

      shortcuts."services/tern-focus.desktop"._launch = "Meta+Return";
    };

    xdg.desktopEntries = {
      tern-focus = {
        comment = "Focus Tern, or launch it if it isn't running";
        exec = lib.getExe tern-focus;
        name = "Focus or launch Tern";
        noDisplay = true;
        startupNotify = false;
      };

      tern-terminal = {
        categories = [
          "System"
          "TerminalEmulator"
        ];

        comment = "Open and focus a terminal tab in the existing Tern window";
        exec = lib.getExe tern-terminal;
        icon = "so.stencil.tern";
        name = "Tern (new tab)";
        noDisplay = true;
        settings.X-TerminalArgExec = "-e";
        startupNotify = false;
        terminal = false;
      };
    };
  };
}
