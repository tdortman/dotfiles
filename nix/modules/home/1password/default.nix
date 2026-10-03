{
  config,
  lib,
  ...
}:

let
  cfg = config.custom.onepassword;
in
{
  options.custom.onepassword.enable = lib.mkEnableOption "1Password Quick Access hotkey for Plasma";

  config = lib.mkIf cfg.enable {
    programs.plasma = {
      # overrideConfig wipes kglobalshortcutsrc on every activation, which drops the
      # GlobalShortcuts portal grant and makes 1Password ask again at each login.
      # Entries copied from what KDE writes after clicking "Allow".
      configFile.kglobalshortcutsrc."com.onepassword.OnePassword" = {
        "98C5EA11B3416A2481F97643D3B23053-" = {
          escapeValue = false;
          value = ''none,none,1Password shortcut:\s'';
        };

        "BAA8851BEC9E30970B8EE945B1B54DCC-Ctrl+Shift+Space" =
          "none,Ctrl+Shift+Space,1Password shortcut: Ctrl+Shift+Space";

        _k_friendly_name = "1Password";
      };

      hotkeys.commands."1password-quick-access" = {
        command = "1password --quick-access";
        comment = "Open 1Password Quick Access";
        key = "Ctrl+Shift+Space";
        name = "1Password Quick Access";
      };
    };
  };
}
