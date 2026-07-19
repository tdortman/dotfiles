{
  config,
  lib,
  ...
}:

let
  cfg = config.onepassword;
in
{
  options.onepassword = {
    enable = lib.mkEnableOption "1Password Quick Access hotkey for Plasma";
  };

  config = lib.mkIf cfg.enable {
    programs.plasma.hotkeys.commands = {
      "1password-quick-access" = {
        command = "1password --quick-access";
        comment = "Open 1Password Quick Access";
        key = "Ctrl+Shift+Space";
        name = "1Password Quick Access";
      };
    };
  };
}
