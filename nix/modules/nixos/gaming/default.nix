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
  options.gaming.enable = lib.mkEnableOption "gaming packages and Steam";

  config = lib.mkIf cfg.enable {
    environment = {
      # https://github.com/jp7677/dxvk-nvapi/wiki/Passing-driver-settings
      sessionVariables = {
        DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE = "on";
        DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION = "render_preset_latest";
        # PROTON_DLSS_INDICATOR = 1;
        DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE = "on";
        DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION = "render_preset_latest";
        PROTON_DLSS_UPGRADE = 1;
        PROTON_ENABLE_WAYLAND = 1;
      };

      systemPackages = with pkgs; [
        wineWow64Packages.stableFull
        mangohud
        protonup-qt
        lutris
        faugus-launcher
        # heroic
        winetricks

        gamescope-wsi
      ];
    };

    programs = {
      gamemode.enable = true;
      gamescope.enable = true;

      steam = {
        enable = true;

        extraCompatPackages = with pkgs; [
          proton-ge-bin
          steamtinkerlaunch
        ];
      };
    };
  };
}
