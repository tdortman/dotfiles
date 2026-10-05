{
  config,
  lib,
  ...
}:

let
  cfg = config.custom.onepassword;
in
{
  options.custom.onepassword.enable = lib.mkEnableOption "1Password Quick Access and preservation of machine-local Plasma shortcut registrations";

  config = lib.mkIf cfg.enable {
    programs.plasma = {
      # Preserve machine-local GlobalShortcuts portal decisions for app-provided IDs.
      # Declarative shortcuts still update, but unmanaged shortcuts are not removed.
      resetFilesExclude = [ "kglobalshortcutsrc" ];

      hotkeys.commands."1password-quick-access" = {
        command = "1password --quick-access";
        comment = "Open 1Password Quick Access";
        key = "Ctrl+Shift+Space";
        name = "1Password Quick Access";
      };
    };
  };
}
