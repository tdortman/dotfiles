{
  pkgs,
  inputs,
  config,
  system,
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
    user = config.common.username;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ config.common.username ];
    };
  };

  users.users.${config.common.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvpbTCshwwLe3cfz/Wh88FWgyg2f91hicM70msF/3D2"
  ];

  nextdns = {
    enable = true;
    configFile = config.age.secrets."nextdns-resolved.conf".path;
    hostName = "NixOS--VM";
  };

  age.secrets = {
    "nextdns-resolved.conf".file = inputs.self + /nix/secrets/nextdns-resolved.conf.age;
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
      file = "/home/${config.common.username}/.local/share/auto_eq/hd6xx_he-1_parametric.txt";
    };

    appCategories = {
      Browser.appNames = [ "LibreWolf" ];
      Music = {
        limitThreshold = -12.0;
        appNames = [
          "spotify"
          "foobar2000 Application"
        ];
      };
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
      System = { };
    };

    fallbackCategory = "System";
  };

  services.kmscon.config = {
    hwaccel = true;
    font-name = "JetBrainsMono Nerd Font Mono";
    font-size = 26;
    font-dpi = 256;
  };

  nixpkgs.overlays = [
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
    # https://github.com/NixOS/nixpkgs/pull/540416
    (final: prev: {
      inherit (inputs.nixpkgs-temp.legacyPackages.x86_64-linux) spicetify-cli;
    })
  ];

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  flatpak = {
    enable = true;
    packages = [
      "com.surfshark.Surfshark"
      "com.gitbutler.gitbutler"
    ];
    extraOverrides."com.gitbutler.gitbutler".Environment = {
      WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };
  };

  networking.hostName = "nixos-vm";

  services.avahi = {
    enable = true;
    openFirewall = true;

    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  mime.librewolf.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  services.libinput.enable = true;

  environment.systemPackages =
    with pkgs;
    [
      ghostty
      librewolf

      xdg-utils
      xdg-desktop-portal
      kdePackages.xdg-desktop-portal-kde

      podman-compose

      (discord.override {
        withVencord = true;
      })

      master.antigravity-fhs
      master.vscode-fhs
      zed-editor-fhs
      btrfs-progs
      master.code-cursor-fhs
    ]
    ++ (with inputs.llm-agents.packages.${system}; [
      cursor-agent
      omp
      opencode
      droid
      copilot-cli
    ]);

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };

  programs.mtr.enable = true;
  system.stateVersion = "25.05";
}
