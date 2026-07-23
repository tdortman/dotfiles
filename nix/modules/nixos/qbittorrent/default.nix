{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.qbittorrent;
in
{
  options.qbittorrent = {
    enable = lib.mkEnableOption "qbittorrent";
    package = lib.mkPackageOption pkgs "qbittorrent-nox" { };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "BitTorrent port";
    };

    webui = lib.mkOption {
      type = lib.types.submodule {
        options = {
          hashedPassword = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Hashed password for the webui (PBKDF2)";
          };

          port = lib.mkOption {
            type = lib.types.int;
            default = 8080;
            description = "WebUI port";
          };

          username = lib.mkOption {
            type = lib.types.str;
            default = "admin";
            description = "Username for the webui";
          };
        };
      };

      default = { };
      description = "WebUI options";
    };

    wireguard = {
      interface = lib.mkOption {
        type = lib.types.str;
        defaultText = "wg0";
        description = "Wireguard interface to use";
      };

      listenPort = lib.mkOption {
        type = lib.types.int;
        default = 51820;
        description = "Wireguard listen port";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wireguard-tools
    ];

    networking.firewall = {
      allowedTCPPorts = [
        cfg.port
        cfg.webui.port
        cfg.wireguard.listenPort
      ];

      allowedUDPPorts = [
        cfg.port
        cfg.wireguard.listenPort
      ];

      checkReversePath = "loose";
    };

    services.qbittorrent = {
      inherit (cfg) package;
      enable = true;
      openFirewall = true;

      serverConfig = {
        BitTorrent.Session = {
          AddExtensionToIncompleteFiles = true;
          AnonymousModeEnabled = true;
          GlobalMaxRatio = 2;
          Interface = cfg.wireguard.interface;
          InterfaceName = cfg.wireguard.interface;
          MaxActiveDownloads = 6;
          MaxActiveTorrents = 6;
          MaxActiveUploads = 6;
          MaxConnections = -1;
          MaxConnectionsPerTorrent = -1;
          MaxUploads = -1;
          MaxUploadsPerTorrent = -1;
        }
        // lib.optionalAttrs (cfg.port != null) {
          Port = cfg.port;
        };

        LegalNotice.Accepted = true;

        Preferences = {
          Connection.Interface = cfg.wireguard.interface;

          General = {
            Locale = "en";
            StatusbarExternalIPDisplayed = true;
          };

          WebUI = with cfg.webui; {
            Address = "*";
            LocalHostAuth = false;
            Password_PBKDF2 = hashedPassword;
            Username = username;
          };
        };
      };

      webuiPort = cfg.webui.port;
    };

    systemd.services.qbittorrent = {
      after = [
        "network-online.target"
        "wireguard-${cfg.wireguard.interface}.service"
      ];

      wants = [ "wireguard-${cfg.wireguard.interface}.service" ];
    };
  };
}
