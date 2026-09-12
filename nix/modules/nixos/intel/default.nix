{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.intel;
in
{
  options.intel.enable = lib.mkEnableOption "Intel graphics and video acceleration";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      intel-gpu-tools
      libva-utils
    ];

    hardware.graphics = {
      enable = true;
      enable32Bit = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
      extraPackages = [ pkgs.intel-media-driver ];

      extraPackages32 = lib.mkIf config.hardware.graphics.enable32Bit [
        pkgs.pkgsi686Linux.intel-media-driver
      ];
    };
  };
}
