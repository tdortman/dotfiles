{
  pkgs,
  currentUsername,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  kde.enable = true;
  spicetify.enable = true;

  onepassword = {
    enable = true;
    user = currentUsername;
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;

    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
      fontSize = 20;
    };
  };

  audio = {
    enable = true;
    input = "alsa_input.pci-0000_02_02.0.analog-stereo";
    inputChannels = "stereo";
    output = "alsa_output.pci-0000_02_02.0.analog-stereo";

    micProcess = {
      enable = true;
      vadThreshold = 50.0;

      compressor = {
        attackTime = 10.6;
        releaseTime = 500;
        threshold = -18.3;
        ratio = 4.0;
        makeupGain = 5.9;
      };
    };

    eq = {
      enable = true;
      file = "/home/${currentUsername}/.local/share/auto_eq/hd6xx_he-1_parametric.txt";
    };

    appCategories = {
      Browser.appNames = [ "LibreWolf" ];
      Music = {
        limitThreshold = -12.0;
        appNames = [
          "spotify"
        ];
      };
      Discord.appNames = [
        "Discord.*"
        "Slack.*"
      ];
      System = { };
    };

    fallbackCategory = "System";
  };

  networking.hostName = "nixos-vm";

  mime.librewolf.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  services.libinput.enable = true;

  environment.systemPackages = with pkgs; [
    ghostty
    vscode-fhs
    librewolf

    xdg-utils
    xdg-desktop-portal
    kdePackages.xdg-desktop-portal-kde

    (discord.override {
      withVencord = true;
    })
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };

  programs.mtr.enable = true;
  system.stateVersion = "25.05";
}
