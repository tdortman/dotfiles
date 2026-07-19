{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.openrgb;

  no-rgb = pkgs.writeShellApplication {
    name = "no-rgb";

    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      openrgb
    ];

    text = ''
      NUM_DEVICES=$(openrgb --noautoconnect --list-devices | grep -cE '^[0-9]+: ')

      for i in $(seq 0 $((NUM_DEVICES - 1))); do
        openrgb --noautoconnect --device "$i" --mode static --color 000000
      done
    '';
  };
in
{
  options.openrgb = {
    enable = lib.mkEnableOption "OpenRGB with automatic RGB disable on boot";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "i2c-dev" ];
    hardware.i2c.enable = true;
    services.udev.packages = [ pkgs.openrgb ];

    systemd = {
      services.no-rgb = {
        description = "no-rgb";

        serviceConfig = {
          ExecStart = "${no-rgb}/bin/no-rgb";
          Type = "oneshot";
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
