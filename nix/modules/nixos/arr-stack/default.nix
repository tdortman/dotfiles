{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.arr-stack;
in
{
  options.arr-stack = {
    enable = lib.mkEnableOption "the media automation stack (Sonarr, Prowlarr, FlareSolverr)";

    sonarrApiSecretPath = lib.mkOption {
      type = lib.types.str;
      default = config.age.secrets."sonarr-api-key".path;
      defaultText = lib.literalExpression "config.age.secrets.\"sonarr-api-key\".path";
      description = "Runtime path of the file containing the Sonarr API key.";
    };

    extraBackupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths to include in backup list.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for each service.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.sonarr-api-key.file = "${inputs.self}/nix/secrets/sonarr-api-key.age";

    services = {
      flaresolverr = {
        inherit (cfg) openFirewall;
        enable = true;
      };

      prowlarr = {
        inherit (cfg) openFirewall;
        enable = true;
      };

      sonarr = {
        inherit (cfg) openFirewall;
        enable = true;
      };
    };

    services.recyclarr = {
      configuration.sonarr.main = {
        api_key._secret = cfg.sonarrApiSecretPath;
        base_url = "http://127.0.0.1:8989";

        custom_formats = [
          # Dolby Vision
          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 1000;
              }
              {
                name = "1080p";
                score = 1000;
              }
            ];

            trash_ids = [
              "7c3a61a9c6cb04f52f1544be6d44a026"
            ];
          }

          # HDR10+
          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 500;
              }
              {
                name = "1080p";
                score = 500;
              }
            ];

            trash_ids = [
              "0c4b99df9206d2cfac3c05ab897dd62a"
            ];
          }

          # HDR10
          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 100;
              }
              {
                name = "1080p";
                score = 100;
              }
            ];

            trash_ids = [
              "505d871304820ba7106b693be6fe4a9e"
            ];
          }

          # SDR
          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 0;
              }
              {
                name = "1080p";
                score = 0;
              }
            ];

            trash_ids = [
              "2016d1676f5ee13a5b7257ff86ac9a93"
            ];
          }

          # Audio formats
          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 1000;
              }
              {
                name = "1080p";
                score = 1000;
              }
            ];

            trash_ids = [
              "0d7824bb924701997f874e7ff7d4844a"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 850;
              }
              {
                name = "1080p";
                score = 850;
              }
            ];

            trash_ids = [
              "9d00418ba386a083fbf4d58235fc37ef"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 700;
              }
              {
                name = "1080p";
                score = 700;
              }
            ];

            trash_ids = [
              "4232a509ce60c4e208d13825b7c06264"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 550;
              }
              {
                name = "1080p";
                score = 550;
              }
            ];

            trash_ids = [
              "1808e4b9cee74e064dfae3f1db99dbfe"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 450;
              }
              {
                name = "1080p";
                score = 450;
              }
            ];

            trash_ids = [
              "c429417a57ea8c41d57e6990a8b0033f"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 350;
              }
              {
                name = "1080p";
                score = 350;
              }
            ];

            trash_ids = [
              "851bd64e04c9374c51102be3dd9ae4cc"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 300;
              }
              {
                name = "1080p";
                score = 300;
              }
            ];

            trash_ids = [
              "30f70576671ca933adbdcfc736a69718"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 100;
              }
              {
                name = "1080p";
                score = 100;
              }
            ];

            trash_ids = [
              "63487786a8b01b7f20dd2bc90dd4a477"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 80;
              }
              {
                name = "1080p";
                score = 80;
              }
            ];

            trash_ids = [
              "5964f2a8b3be407d083498e4459d05d0"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 70;
              }
              {
                name = "1080p";
                score = 70;
              }
            ];

            trash_ids = [
              "dbe00161b08a25ac6154c55f95e6318d"
            ];
          }

          {
            assign_scores_to = [
              {
                name = "Ultra-HD";
                score = 60;
              }
              {
                name = "1080p";
                score = 60;
              }
            ];

            trash_ids = [
              "a50b8a0c62274a7c38b09a9619ba9d86"
            ];
          }
        ];
      };

      enable = true;
      schedule = "daily";
    };
  };
}
