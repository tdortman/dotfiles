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

    # FIXME: See https://github.com/NixOS/nixpkgs/issues/513245
    nixpkgs.overlays = [
      (_: prev: {
        openldap = prev.openldap.overrideAttrs {
          doCheck = !prev.stdenv.hostPlatform.isi686;
        };
      })
    ];

    programs.gamemode.enable = true;
    environment.systemPackages = with pkgs; [
      wineWow64Packages.stableFull
      mangohud
      protonup-qt
      lutris
      bottles
      faugus-launcher
      # heroic
      winetricks

      gamescope-wsi
    ];

    # https://github.com/jp7677/dxvk-nvapi/wiki/Passing-driver-settings
    environment.sessionVariables = {
      PROTON_DLSS_UPGRADE = 1;
      # PROTON_DLSS_INDICATOR = 1;
      DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE = "on";
      DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION = "render_preset_latest";

      DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE = "on";
      DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION = "render_preset_latest";
    };
  };
}
