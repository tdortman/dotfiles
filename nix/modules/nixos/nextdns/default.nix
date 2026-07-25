{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nextdns;
in
{
  options.nextdns = {
    enable = lib.mkEnableOption "NextDNS via systemd-resolved";

    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the systemd-resolved config file for NextDNS.";
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      defaultText = "NixOS--PC";
      description = "The hostname to use for NextDNS (-- for spaces)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager = {
      dns = "systemd-resolved";
      settings."global-dns-domain-*".servers = "127.0.0.53";
    };

    services.resolved = {
      enable = true;

      settings.Resolve = {
        Domains = [ "~." ];
      }
      // lib.optionalAttrs config.services.avahi.enable {
        MulticastDNS = false;
      };
    };

    systemd.services.nextdns-config-generator = {
      description = "Generate NextDNS config for systemd-resolved";
      before = [ "systemd-resolved.service" ];
      after = [ "local-fs.target" ];
      wantedBy = [ "sysinit.target" ];

      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };

      unitConfig.DefaultDependencies = false;

      script = ''
        mkdir -p /run/systemd/resolved.conf.d

        ${pkgs.gnused}/bin/sed 's/HOSTNAME/${cfg.hostName}/g' ${cfg.configFile} > /run/systemd/resolved.conf.d/01-nextdns.conf
      '';
    };
  };
}
