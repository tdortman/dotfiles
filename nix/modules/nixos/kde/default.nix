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
  options.custom.kde.enable = lib.mkEnableOption "KDE Plasma desktop environment";

  config = lib.mkIf cfg.enable {
    environment = {
      plasma6.excludePackages =
        with pkgs.kdePackages;
        [
          plasma-browser-integration
        ]
        ++ lib.optionals (lib.versionOlder pkgs.kdePackages.kwin.version "6.7.90") [
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
