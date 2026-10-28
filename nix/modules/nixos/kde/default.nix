{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.kde;
in
{
  options.custom.kde = {
    enable = lib.mkEnableOption "KDE Plasma desktop environment";
    patches.enable = lib.mkEnableOption "local kde-gtk-config patch that keeps GTK modules resident";
  };

  config = lib.mkIf cfg.enable {
    environment = {
      plasma6.excludePackages = with pkgs.kdePackages; [
        plasma-browser-integration
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
          _: kprev:
          {
            # Merkuro's Contacts applet is installed into the profile's plugin
            # directory and declares X-Plasma-NotificationAreaCategory, so
            # PlasmoidRegistry::registerPlugin() auto-enables it in the system
            # tray on every login (it does that for any tray applet that is
            # enabled by default and not yet in its knownItems list). Ship
            # merkuro without the applet plugin; the applications are untouched.
            merkuro = kprev.merkuro.overrideAttrs (oldAttrs: {
              postInstall = (oldAttrs.postInstall or "") + ''
                applet="$out/lib/qt-6/plugins/plasma/applets/org.kde.merkuro.contact.applet.so"
                if [ ! -e "$applet" ]; then
                  echo "error: merkuro no longer installs $applet" >&2
                  echo "error: update the tray applet patch in modules/nixos/kde/default.nix" >&2
                  exit 1
                fi
                rm "$applet"
              '';
            });

            spectacle = kprev.spectacle.override {
              tesseractLanguages = [ "all" ];
            };
          }
          // lib.optionalAttrs cfg.patches.enable {
            kde-gtk-config = kprev.kde-gtk-config.overrideAttrs (oldAttrs: {
              # GTK can unload these modules while their file/theme callbacks
              # remain connected, crashing Discord when colors.css changes.
              # Keep their code resident; test-gtk-module-unload.py exercises
              # CSS reload after GTK clears its module list.
              patches = (oldAttrs.patches or [ ]) ++ [ ./gtk-modules-resident.patch ];
            });
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
