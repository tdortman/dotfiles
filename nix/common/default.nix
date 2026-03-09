{
  pkgs,
  currentUsername,
  lib,
  ...
}:

{
  imports = [
    ./security.nix
    ./packages.nix
  ];

  age.identityPaths = [
    "/home/${currentUsername}/.config/age/key"
    "/root/.config/age/key"
    "/etc/age/key"
  ];

  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cache.flox.dev"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
    ];
    auto-optimise-store = true;
    trusted-users = [
      currentUsername
      "root"
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  fonts = {
    fontDir.enable = true;

    packages = with pkgs; [
      inter
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
      noto-fonts-cjk-sans
      corefonts
    ];
  };

  users.users.${currentUsername} = {
    isNormalUser = true;
    extraGroups = [
      "docker"
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "render"
      "input"
      "gamemode"
      "wireshark"
      "kvm"
      "libvirtd"
      "plugdev"
    ];
    initialPassword = "password";
  };

  programs.wireshark = {
    package = pkgs.wireshark;
    enable = true;
    usbmon.enable = true;
  };

  hardware.enableRedistributableFirmware = true;

  time.timeZone = "Europe/Berlin";

  environment.variables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };

  environment.sessionVariables.NH_FLAKE = "$HOME/dotfiles";

  environment.shellAliases = {
    nix-shell = "nix-shell --command zsh";

    nixos-switch = "nh os switch";
    nixos-boot = "nh os boot";

    flake-update = "sudo nix flake update --flake $NH_FLAKE";
    update = "nh os switch --update";
    hydra-check = "${lib.getExe pkgs.hydra-check} -c unstable -a x86_64-linux";
  };

  environment.interactiveShellInit = ''
    flake-template() {
      nix flake init --template $NH_FLAKE#$1
    }
  '';

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  programs.nix-ld.enable = true;
  programs.gnupg.agent.enable = true;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  nixpkgs.config.freetype = {
    withHarfbuzz = true;
    withGnuByteCode = true;
  };

  programs.nh.enable = true;
  programs.direnv.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  programs.nano = {
    enable = true;
    nanorc = ''
      set tabsize 4
      set tabstospaces
    '';
  };

  hardware.keyboard.qmk.enable = true;

  services.xserver.xkb = {
    layout = "us,de";
    variant = "altgr-intl,";
  };

  console.useXkbConfig = true;

  i18n = {
    defaultLocale = "en_GB.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "de_DE.UTF-8";
      LC_TIME = "C.UTF-8";
      LC_TELEPHONE = "C.UTF-8";
      LC_MEASUREMENT = "C.UTF-8";
      LC_PAPER = "C.UTF-8";
      LC_IDENTIFICATION = "C.UTF-8";
    };
  };
  services.dbus.implementation = "broker";

  programs.nix-index-database.comma.enable = true;
  programs.nix-index.enableBashIntegration = true;
  programs.nix-index.enableZshIntegration = true;
}
