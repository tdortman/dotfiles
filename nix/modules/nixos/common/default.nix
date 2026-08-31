{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./packages.nix
    ./security.nix
  ];

  options.common.username = lib.mkOption {
    type = lib.types.str;
    description = "Primary user for this host";
  };

  config = {
    age = {
      identityPaths = [
        "/home/${config.common.username}/.config/age/key"
        "/root/.config/age/key"
        "/etc/age/key"
      ];

      secrets.login-password.file = "${inputs.self}/nix/secrets/login-password.age";
    };

    common.username = lib.mkDefault "tim";
    console.useXkbConfig = true;

    environment = {
      etc."librewolf/policies/policies.json".text = builtins.toJSON {
        policies.ExtensionSettings."firefox-extension@deepl.com".runtime_blocked_hosts = [
          "*://openrouter.ai"
          "*://*.openrouter.ai"
        ];
      };

      interactiveShellInit = ''
        flake-template() {
          nix flake init --template $NH_FLAKE#$1
        }
      '';

      sessionVariables = {
        NH_FLAKE = "$HOME/dotfiles";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };

      shellAliases = {
        flake-update = "nix flake update --flake $NH_FLAKE";
        hydra-check = "${lib.getExe pkgs.hydra-check} -c unstable -a x86_64-linux";
        nix-shell = ''command nix-shell --command "''${SHELL:-bash}"'';
        nixos-boot = "nh os boot";
        nixos-switch = "nh os switch";
        update = "flake-update && nixos-switch";
      };
    };

    fonts = {
      fontDir.enable = true;

      packages = with pkgs; [
        corefonts
        inter
        nerd-fonts.caskaydia-mono
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        noto-fonts-cjk-sans
      ];
    };

    hardware = {
      enableRedistributableFirmware = true;
      keyboard.qmk.enable = true;
    };

    i18n = {
      defaultLocale = "en_GB.UTF-8";

      extraLocaleSettings = {
        LC_ADDRESS = "de_DE.UTF-8";
        LC_IDENTIFICATION = "C.UTF-8";
        LC_MEASUREMENT = "C.UTF-8";
        LC_PAPER = "C.UTF-8";
        LC_TELEPHONE = "C.UTF-8";
      };
    };

    nix = {
      package = pkgs.lixPackageSets.latest.lix;

      gc = {
        options = "--delete-older-than 14d";
        automatic = true;
        dates = "weekly";
      };

      optimise = {
        automatic = true;
        dates = [ "00:00" ];
      };

      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        extra-substituters = [
          "https://nix-community.cachix.org"
          "https://cache.flox.dev"
          "https://cache.nixos-cuda.org"
          "https://cache.numtide.com"
          "https://agent-sandbox.cachix.org"
        ];

        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
          "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          "agent-sandbox.cachix.org-1:x7WgdtZjoPgbKdyk5oxP2QvN7B3SfuHmGvXKJ8xtTu0="
        ];

        trusted-users = [
          "@wheel"
        ];
      };
    };

    nixpkgs.config.freetype = {
      withGnuByteCode = true;
      withHarfbuzz = true;
    };

    programs = {
      appimage = {
        enable = true;
        binfmt = true;
      };

      direnv.enable = true;
      gnupg.agent.enable = true;

      nano = {
        enable = true;

        nanorc = ''
          set tabsize 4
          set tabstospaces
        '';
      };

      nh.enable = true;

      nix-index = {
        enableBashIntegration = true;
        enableZshIntegration = true;
      };

      nix-index-database.comma.enable = true;
      nix-ld.enable = true;

      wireshark = {
        enable = true;
        package = pkgs.wireshark;
        usbmon.enable = true;
      };

      ydotool.enable = true;
      zsh.enable = true;
    };

    services = {
      dbus.implementation = "broker";

      kmscon = {
        enable = true;
        useXkbConfig = true;
      };

      udev.packages = with pkgs; [
        game-devices-udev-rules
      ];

      xserver.xkb = {
        layout = "us,de";
        variant = "altgr-intl,";
      };
    };

    time.timeZone = "Europe/Berlin";

    users = {
      defaultUserShell = pkgs.zsh;
      mutableUsers = false;

      users = {
        ${config.common.username} = {
          extraGroups = [
            "audio"
            "gamemode"
            "input"
            "kvm"
            "libvirtd"
            "networkmanager"
            "plugdev"
            "render"
            "uinput"
            "video"
            "wheel"
            "wireshark"
            "ydotool"
          ];

          hashedPasswordFile = config.age.secrets."login-password".path;
          isNormalUser = true;
        };

        root.hashedPasswordFile = config.age.secrets."login-password".path;
      };
    };
  };
}
