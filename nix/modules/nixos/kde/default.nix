{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.kde;
in
{
  options.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop environment";
  };

  config = lib.mkIf cfg.enable {
    services = {
      desktopManager.plasma6.enable = true;
      displayManager.plasma-login-manager.enable = true;
    };

    programs.kdeconnect.enable = true;

    environment.systemPackages = with pkgs.kdePackages; [
      kcalc
      kcharselect
      kcolorchooser
      ksystemlog
      sddm-kcm
      pkgs.wayland-utils
      pkgs.wl-clipboard
      kdeconnect-kde

      kaccounts-integration
      kaccounts-providers
      kio-gdrive

      signond
      signon-kwallet-extension
      kdepim-addons
    ];
  };
}
