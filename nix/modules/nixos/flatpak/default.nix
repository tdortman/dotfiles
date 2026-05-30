{
  config,
  lib,
  ...
}:

let
  cfg = config.flatpak;
in
{
  options.flatpak = {
    enable = lib.mkEnableOption "Flatpak with themed overrides for Plasma/GTK";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "com.surfshark.Surfshark"
        "com.gitbutler.gitbutler"
      ];
      description = "Flatpak application IDs to install.";
    };

    extraOverrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Per-application Flatpak overrides (additional to the global theme overrides).";
      example = {
        "com.gitbutler.gitbutler".Environment = {
          WEBKIT_DISABLE_DMABUF_RENDERER = "1";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.flatpak = {
      enable = true;
      packages = cfg.packages;
      update.auto = {
        enable = true;
        onCalendar = "weekly";
      };
      overrides = {
        global = {
          Context = {
            filesystems = [
              "xdg-config/fontconfig:ro"
              "xdg-config/gtkrc:ro"
              "xdg-config/gtkrc-2.0:ro"
              "xdg-config/gtk-2.0:ro"
              "xdg-config/gtk-3.0:ro"
              "xdg-config/gtk-4.0:ro"
              "xdg-data/themes:ro"
              "xdg-data/icons:ro"
            ];
          };
          Environment = {
            GTK_THEME = "Breeze";
          };
        };
      }
      // cfg.extraOverrides;
    };
  };
}
