{
  pkgs,
  lib,
  config,
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
      default = null;
      type = lib.types.nullOr lib.types.int;
      description = "BitTorrent port";
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

    webui = lib.mkOption {
      type = lib.types.submodule {
        options = {
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
          hashedPassword = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Hashed password for the webui (PBKDF2)";
          };
        };
      };
      description = "WebUI options";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.qbittorrent = {
      enable = true;
      inherit (cfg) package;
      webuiPort = cfg.webui.port;
      openFirewall = true;
      serverConfig = {
        BitTorrent.Session = {
          AddExtensionToIncompleteFiles = true;
          AnonymousModeEnabled = true;

          MaxActiveDownloads = 6;
          MaxActiveUploads = 6;
          MaxActiveTorrents = 6;

          GlobalMaxRatio = 2;
          MaxConnections = -1;
          MaxConnectionsPerTorrent = -1;
          MaxUploads = -1;
          MaxUploadsPerTorrent = -1;

          Interface = cfg.wireguard.interface;
          InterfaceName = cfg.wireguard.interface;
        }
        // lib.optionalAttrs (cfg.port != null) {
          Port = cfg.port;
        };
        Preferences = {
          General = {
            StatusbarExternalIPDisplayed = true;
            Locale = "en";
          };
          Connection = {
            Interface = cfg.wireguard.interface;
          };
          WebUI = with cfg.webui; {
            Address = "*";
            LocalHostAuth = false;
            Username = username;
            Password_PBKDF2 = hashedPassword;
          };
        };
        LegalNotice.Accepted = true;
      };
    };

    systemd.services.qbittorrent = {
      after = [
        "network-online.target"
        "wireguard-${cfg.wireguard.interface}.service"
      ];
      wants = [ "wireguard-${cfg.wireguard.interface}.service" ];
    };

    networking.firewall = {
      allowedUDPPorts = [
        cfg.wireguard.listenPort
        cfg.port
      ];
      allowedTCPPorts = [
        cfg.webui.port
        cfg.wireguard.listenPort
        cfg.port
      ];
      checkReversePath = "loose";
    };

    environment.systemPackages = [
      pkgs.wireguard-tools
    ];
  };
}
