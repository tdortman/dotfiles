{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gaming;
in
{
  options.gaming = {
    enable = lib.mkEnableOption "gaming packages and Steam";
  };

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    programs.gamescope.enable = true;

    programs.gamemode.enable = true;
    environment.systemPackages = with pkgs; [
      wineWow64Packages.stable
      mangohud
      protonup-qt
      lutris
      bottles
      faugus-launcher
      # heroic
      winetricks
    ];
  };
}
