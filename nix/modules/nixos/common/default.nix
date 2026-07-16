{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:

{
  imports = [
    ./security.nix
    ./packages.nix
  ];

  options.common.username = lib.mkOption {
    type = lib.types.str;
    description = "Primary user for this host";
  };

  config = {
    common.username = lib.mkDefault "tim";

    age = {
      identityPaths = [
        "/home/${config.common.username}/.config/age/key"
        "/root/.config/age/key"
        "/etc/age/key"
      ];

      secrets = {
        login-password.file = "${inputs.self}/nix/secrets/login-password.age";
      };
    };

    nix.package = pkgs.lixPackageSets.latest.lix;
    nix.settings = {
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://cache.flox.dev"
        "https://cache.nixos-cuda.org"
        "https://cache.numtide.com"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      trusted-users = [
        "@wheel"
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

    users.mutableUsers = false;
    users.users.root.hashedPasswordFile = config.age.secrets."login-password".path;
    users.users.${config.common.username} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "audio"
        "video"
        "render"
        "input"
        "uinput"
        "gamemode"
        "wireshark"
        "kvm"
        "libvirtd"
        "plugdev"
        "ydotool"
      ];
      hashedPasswordFile = config.age.secrets."login-password".path;
    };

    programs.wireshark = {
      package = pkgs.wireshark;
      enable = true;
      usbmon.enable = true;
    };

    programs.ydotool.enable = true;

    hardware.enableRedistributableFirmware = true;

    time.timeZone = "Europe/Berlin";

    environment.variables = {
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };

    environment.sessionVariables.NH_FLAKE = "$HOME/dotfiles";

    environment.shellAliases = {
      nix-shell = ''command nix-shell --command "''${SHELL:-bash}"'';

      nixos-switch = "nh os switch";
      nixos-boot = "nh os boot";

      flake-update = "sudo nix flake update --flake $NH_FLAKE";
      update = "flake-update && nixos-switch";
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

    nix.optimise = {
      automatic = true;
      dates = [ "00:00" ];
    };

    programs.nano = {
      enable = true;
      nanorc = ''
        set tabsize 4
        set tabstospaces
      '';
    };

    hardware.keyboard.qmk.enable = true;

    services.kmscon = {
      enable = true;
      useXkbConfig = true;
    };

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
  };
}
