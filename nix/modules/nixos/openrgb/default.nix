{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.openrgb;

  no-rgb = pkgs.writeShellApplication {
    name = "no-rgb";
    runtimeInputs = [ pkgs.openrgb ];

    text = ''
      openrgb --noautoconnect --mode static --color 000000
    '';
  };
in
{
  options.custom.openrgb.enable = lib.mkEnableOption "OpenRGB with automatic RGB disable on boot";

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "i2c-dev" ];
    hardware.i2c.enable = true;
    services.udev.packages = [ pkgs.openrgb ];

    systemd = {
      services.no-rgb = {
        description = "no-rgb";

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${no-rgb}/bin/no-rgb";
        };
      };

      timers.no-rgb = {
        description = "Run no-rgb every 2 hours";

        timerConfig = {
          OnBootSec = "0";
          OnUnitActiveSec = "2h";
        };

        wantedBy = [ "timers.target" ];
      };
    };
  };
}
