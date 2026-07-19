{
  config,
  pkgs,
  inputs,
  system,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  age.secrets = {
    "nextdns-resolved.conf".file = inputs.self + /nix/secrets/nextdns-resolved.conf.age;
  };

  audio = {
    enable = true;
    input = "alsa_input.pci-0000_02_02.0.analog-stereo";
    inputChannels = "stereo";
    output = "alsa_output.pci-0000_02_02.0.analog-stereo";

    appCategories = {
      Browser.appNames = [ "LibreWolf" ];

      Discord = {
        appNames = [
          "Discord.*"
          "Slack.*"
        ];

        binaries = [
          ".Discord-wrapped"
          "fluxer"
        ];
      };

      Music = {
        appNames = [
          "foobar2000 Application"
          "spotify"
        ];

        limitThreshold = -12.0;
      };

      System = { };
    };

    fallbackCategory = "System";

    eq = {
      enable = true;
      file = "/home/${config.common.username}/.local/share/auto_eq/hd6xx_he-1_parametric.txt";
    };

    micProcess = {
      enable = true;

      compressor = {
        attackTime = 10.6;
        makeupGain = 5.9;
        ratio = 4.0;
        releaseTime = 500;
        threshold = -18.3;
      };

      vadThreshold = 50.0;
    };
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  environment = {
    systemPackages =
      with pkgs;
      [
        (discord.override {
          withVencord = true;
        })
        btrfs-progs
        ghostty
        kdePackages.xdg-desktop-portal-kde
        librewolf
        master.antigravity-fhs
        master.code-cursor-fhs
        master.vscode-fhs
        podman-compose
        xdg-desktop-portal
        xdg-utils
        zed-editor-fhs
      ]
      ++ (with inputs.llm-agents.packages.${system}; [
        copilot-cli
        cursor-agent
        droid
        omp
        opencode
      ]);

    variables = {
      NIXOS_OZONE_WL = "1";
    };
  };

  flatpak = {
    enable = true;

    extraOverrides."com.gitbutler.gitbutler".Environment = {
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };

    packages = [
      "com.gitbutler.gitbutler"
      "com.surfshark.Surfshark"
    ];
  };

  kde.enable = true;
  mime.librewolf.enable = true;

  networking = {
    hostName = "nixos-vm";
    networkmanager.enable = true;
  };

  nextdns = {
    enable = true;
    configFile = config.age.secrets."nextdns-resolved.conf".path;
    hostName = "NixOS--VM";
  };

  nixpkgs.overlays = [
    # https://github.com/NixOS/nixpkgs/pull/540416
    (final: prev: {
      inherit (inputs.nixpkgs-temp.legacyPackages.x86_64-linux) spicetify-cli;
    })
    # https://github.com/NixOS/nixpkgs/issues/540025
    (final: prev: {
      python314Packages = prev.python314Packages.overrideScope (
        pyFinal: pyPrev: {
          patool = pyPrev.patool.overridePythonAttrs (_old: {
            doCheck = false;
            doInstallCheck = false;
          });
        }
      );
    })
  ];

  onepassword = {
    enable = true;
    user = config.common.username;
  };

  programs.mtr.enable = true;

  services = {
    avahi = {
      enable = true;
      openFirewall = true;

      publish = {
        addresses = true;
        enable = true;
        workstation = true;
      };
    };

    kmscon.config = {
      font-dpi = 256;
      font-name = "JetBrainsMono Nerd Font Mono";
      font-size = 26;
      hwaccel = true;
    };

    libinput.enable = true;

    openssh = {
      enable = true;
      openFirewall = true;

      settings = {
        AllowUsers = [ config.common.username ];
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  spicetify.enable = true;
  system.stateVersion = "25.05";

  users.users.${config.common.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvpbTCshwwLe3cfz/Wh88FWgyg2f91hicM70msF/3D2"
  ];

  virtualisation = {
    containers.enable = true;

    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
      dockerCompat = true;
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    xdgOpenUsePortal = true;
  };
}
