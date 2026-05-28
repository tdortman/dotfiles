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
              rev = "5015b9122a9c39274bdc7507e1de4fec0cc20f95";
              hash = "sha256-JkkIs40Kp57kLTcb95WIgfHDoCP/LHZ3TmdP1w1e1OY=";
            })
            + "/romaji-lyrics";
          name = "romaji_lyrics.js";
        }
        {
          src =
            (pkgs.fetchFromGitHub {
              owner = "resxt";
              repo = "spicetify-extensions";
              rev = "75bd17ba1c9a19730f14529fb18857d7b9c7c12e";
              hash = "sha256-+Th5o00c3Y8U+Y/RGmRSkWWp97YCoCJmoESFLZf9dwM=";
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
