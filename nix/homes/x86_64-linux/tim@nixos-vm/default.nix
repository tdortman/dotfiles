{
  pkgs,
  ...
}:

{
  home.stateVersion = "25.11";

  programs.plasma = {
    configFile = {
      kcminputrc."Libinput/1133/16531/Logitech PRO X" = {
        PointerAcceleration = 0.500;
        PointerAccelerationProfile = 1;
        ScrollFactor = 1;
      };

      kwinrulesrc = {
        "28f2a5bd-b708-4cde-b12e-cc2e3bc1def1" = {
          desktopfile = "/run/current-system/sw/share/applications/StreamController.desktop";
          desktopfilerule = 4;
        };

        General = {
          count = 1;
          rules = "9f92402d-ab4d-45b7-9660-516c5f837c7b";
        };
      };

    };

    workspace.wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/MilkyWay/contents/images/5120x2880.png";
  };

  services.wl-clip-persist.enable = false;
}
