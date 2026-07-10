{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.spicetify;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.spicetify = {
    enable = lib.mkEnableOption "Spicetify Spotify customization";
  };

  config = lib.mkIf cfg.enable {
    programs.spicetify = {
      enable = true;

      spotifyLaunchFlags = "--enable-blink-features=MiddleClickAutoscroll";
      experimentalFeatures = true;
      alwaysEnableDevTools = true;

      enabledExtensions = with spicePkgs.extensions; [
        {
          src =
            (pkgs.fetchFromGitHub {
              owner = "41pha1";
              repo = "spicetify-extensions";
              rev = "8f10fa3db610695033f46612d7ab4100f1eb65fe";
              hash = "sha256-2mFk+tzFMc3o41DvelHFNykdk/DSfq+QOltNc8ON/t4=";
            })
            + "/romaji-lyrics";
          name = "romaji_lyrics.js";
        }
        {
          src =
            (pkgs.fetchFromGitHub {
              owner = "resxt";
              repo = "spicetify-extensions";
              rev = "fb94b32511b74f791ddeb025aec0c77928d6bd60";
              hash = "sha256-SLu2+H5tdwPz0JrT61SuAx9uSW7Wfv2wLoA7d/AwmZQ=";
            })
            + "/startup-page/dist";
          name = "startup-page.js";
        }
        shuffle
        seekSong
        keyboardShortcut
        fullAlbumDate
      ];

      enabledCustomApps = with spicePkgs.apps; [
        historyInSidebar
        marketplace

        {
          src = pkgs.fetchzip {
            url = "https://github.com/harbassan/spicetify-apps/releases/download/stats-v1.1.3/spicetify-stats.release.zip";
            hash = "sha256-8CO5M0EM0n/aXD79Xsis0eiBpxj2zVLfu49/kbO+m+M=";
          };
          name = "index.js";
        }
      ];

      enabledSnippets = with spicePkgs.snippets; [
        roundedButtons
        smoothPlaylistRevealGradient
        prettyLyrics
        fixMainViewWidth
        roundedImages
      ];

      theme = spicePkgs.themes.lucid;
    };
  };
}
