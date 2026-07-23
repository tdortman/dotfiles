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
  options.kde.enable = lib.mkEnableOption "KDE Plasma desktop environment";

  config = lib.mkIf cfg.enable {
    environment = {
      plasma6.excludePackages = with pkgs.kdePackages; [
        plasma-browser-integration
        kwin-x11
      ];

      systemPackages = with pkgs.kdePackages; [
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

        oxygen
        oxygen-icons
        oxygen-sounds
      ];
    };

    nixpkgs.overlays = [
      (final: prev: {
        kdePackages = prev.kdePackages.overrideScope (
          _: kprev: {
            spectacle = kprev.spectacle.override {
              tesseractLanguages = [ "all" ];
            };
          }
        );
      })
    ];

    programs.kdeconnect.enable = true;

    services = {
      desktopManager.plasma6.enable = true;
      displayManager.plasma-login-manager.enable = true;
    };
  };
}
