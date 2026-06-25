{
  pkgs,
  config,
  inputs,
  system,
  currentUsername,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  kde.enable = true;
  gaming.enable = true;
  openrgb.enable = true;
  disableWakeFromHibernate.enable = true;
  spicetify.enable = true;

  backups = {
    enable = true;
    librewolfProfile = "f9ugjznf.default";
    flatpakApps = [ "com.core447.StreamController" ];
    passwordFile = config.age.secrets.restic-password.path;

    snapshots.enable = true;

    localBackup = {
      enable = true;
      device = "/dev/disk/by-uuid/dfbdb886-3344-4e83-8403-f5ea43187f61";
      fsType = "btrfs";
      timer = "*-*-* 18:00:00";
    };
  };

  onepassword = {
    enable = true;
    user = currentUsername;
  };

  audio = {
    enable = true;
    input = "alsa_input.usb-Antlion_Audio_Antlion_USB_adapter_20180707-00.mono-fallback";
    inputChannels = "mono";
    output = "alsa_output.usb-Schiit_Audio_Schiit_Modi_Uber-00.analog-stereo";
    mutedInputs = [ "alsa_input.usb-046d_Brio_100_2602ZBR396W8-02.mono-fallback" ];

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

  nvidia = {
    cuda = {
      enable = true;
      nvidia-fs.enable = true;
      packages = pkgs.cudaPackages_13_2;
    };
    driver = {
      enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
  };

  hdr = {
    enable = true;
    defaultOutput = "DP-3";
    extraScripts = true;
  };

  nextdns = {
    enable = true;
    configFile = config.age.secrets."nextdns-resolved.conf".path;
    hostName = "NixOS--PC";
  };

  vpn-run = {
    enable = true;
    defaultInterface = "wg0";
    allowedUsers = [ currentUsername ];
  };

  jgu-vpn = {
    enable = true;
    username = "tdortman@uni-mainz.de";
    secretsFile = config.age.secrets."jgu-vpn-swanctl".path;
    dnsServers = [
      "134.93.144.2"
      "134.93.144.3"
    ];
  };

  agent-sandbox = {
    enable = true;
    sudoPolicy = "approve";
    network.enable = true;
    syscallGate.enable = true;
    filesystem.dynamicApproval.enable = true;
    readonlyDirs = [
      "~/.local/bin"
      "/lib64"
      "/usr/lib"
      "~/.config/agent-sandbox"
    ];
    readwriteDirs = [
      "~/.agents"
    ];
    readonlyFiles = [
      "~/.gitconfig"
      "~/.1password/agent.sock"
      "/usr/bin/env"
    ];
    packages =
      let
        agents = pkgs.llm-agents;
      in
      [
        {
          package = agents.omp;
          readwriteDirs = [ "~/.omp" ];
        }
        {
          package = agents.cursor-agent;
          readwriteDirs = [
            "~/.cursor"
            "~/.config/cursor"
          ];
        }
        {
          package = agents.codex;
          readwriteDirs = [ "~/.codex" ];
        }
        {
          package = agents.opencode;
          readwriteDirs = [
            "~/.config/opencode"
            "~/.local/share/opencode"
            "~/.local/state/opencode/"
            "~/.local/share/zoxide"
            "~/.cache/opencode"
            "~/.opencode"

            # cursor-acp
            "~/.opencode-cursor"
            "~/.local/share/cursor-agent/"
          ];
          readonlyFiles = [
            "~/.config/cursor/auth.json" # For opencode-cursor
          ];
        }
        {
          package = agents.droid;
          readwriteDirs = [ "~/.factory" ];
        }
        {
          package = agents.copilot-cli;
          readwriteDirs = [
            "~/.config/gh-copilot"
            "~/.copilot"
          ];
          readonlyFiles = [
            "/run/user/1000/wayland-0"
            "/run/user/1000/bus"
          ];
        }
      ];
  };

  qbittorrent = {
    enable = true;
    port = 32882;
    wireguard.interface = "wg0";
    webui = {
      port = 8080;
      username = "admin";
      hashedPassword = "@ByteArray(ld9tpxX1BfxpzgEImGXLJA==:yxC2mw6+EfF14jJNV9ppuS0sqNas7ENWXAccUu+gCVNP0h7NokJA1dgnkoWejmDfp5mq6OEFXEHPGkLJNUZNiw==)";
    };
  };

  age.secrets = {
    "restic-password".file = inputs.self + /nix/secrets/restic-password.age;
    "nextdns-resolved.conf".file = inputs.self + /nix/secrets/nextdns-resolved.conf.age;
    "airvpn-privatekey".file = inputs.self + /nix/secrets/airvpn-privatekey.age;
    "airvpn-presharedkey".file = inputs.self + /nix/secrets/airvpn-presharedkey.age;
    "jgu-vpn-swanctl".file = inputs.self + /nix/secrets/jgu-vpn-swanctl.age;
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
  };

  programs.virt-manager.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.lact.enable = true;

  services.kmscon.config = {
    hwaccel = true;
    font-name = "JetBrainsMono Nerd Font Mono";
    font-size = 26;
    font-dpi = 256;
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
    ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  networking.wireguard.interfaces = {
    wg0 = {
      privateKeyFile = "/home/${currentUsername}/.config/wireguard/privatekey";
      ips = [ "10.14.0.2/16" ];

      allowedIPsAsRoutes = false;
      dynamicEndpointRefreshSeconds = 300;

      peers = [
        {
          publicKey = "fJDA+OA6jzQxfRcoHfC27xz7m3C8/590fRjpntzSpGo=";
          endpoint = "de-fra.prod.surfshark.com:51820";

          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
      ];
    };

    wg1 = {
      privateKeyFile = toString config.age.secrets."airvpn-privatekey".path;
      ips = [ "10.183.233.232/32" ];

      allowedIPsAsRoutes = false;
      dynamicEndpointRefreshSeconds = 300;

      peers = [
        {
          publicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
          presharedKeyFile = toString config.age.secrets."airvpn-presharedkey".path;
          endpoint = "de3.vpn.airdns.org:51820";
          persistentKeepalive = 15;

          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
      ];
    };
  };

  arr-stack.enable = true;

  programs.streamcontroller.enable = true;

  services.udev.extraRules = ''
    # StreamController text input
    KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
  '';

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  hardware.nvidia-container-toolkit.enable = true;

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

  networking.hostName = "nixos-pc";

  mime.librewolf.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  services.libinput.enable = true;

  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  hardware.firmware = with pkgs; [
    rtl8761b-firmware
  ];

  services.ratbagd.enable = true;

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  programs.dconf.enable = true;

  programs.thunderbird.enable = true;

  nixpkgs.overlays = [
    (final: prev: {
      librewolf = inputs.nixpkgs-librewolf.legacyPackages.${system}.librewolf;
      librewolf-unwrapped = inputs.nixpkgs-librewolf.legacyPackages.${system}.librewolf-unwrapped;
    })
  ];

  environment.systemPackages = with pkgs; [
    ntfs3g
    ghostty
    btrfs-progs
    mpv
    pkgs.librewolf

    gvfs
    samba
    glib

    inputs.agenix.packages."${system}".default
    cuda.llama-cpp
    cuda.lmstudio
    dbeaver-bin
    lsfg-vk-ui
    lsfg-vk
    winboat

    libratbag
    piper
    vlc
    libnotify
    ghidra
    libreoffice-qt6
    nheko

    xdg-utils
    xdg-desktop-portal
    kdePackages.xdg-desktop-portal-kde
    teams-for-linux

    (discord.override {
      withVencord = true;
      commandLineArgs = "--enable-blink-features=MiddleClickAutoscroll";
    })

    google-chrome # Used by antigravity
    master.antigravity-fhs
    master.vscode-fhs
    zed-editor-fhs
    master.code-cursor-fhs

    custom.danbooru-rs
    custom.shiru
    custom.fluxer

    pkgs.llm-agents.git-surgeon
  ];

  hardware.logitech.wireless.enable = true;

  xdg.portal.xdgOpenUsePortal = true;

  environment.variables = {
    # nvidia_icd.x86_64.json -> nvidia_icd.json as of 595.71.05
    VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";

    NIXOS_OZONE_WL = "1";

    # Setting gfx.webrender.compositor.force-enabled to true breaks the direct backend
    NVD_BACKEND = "direct";
    MOZ_ENABLE_WAYLAND = 1;
    MOZ_DISABLE_RDD_SANDBOX = 1;
    GHIDRA_ROOT = "${pkgs.ghidra}";
  };

  programs.mtr.enable = true;
  system.stateVersion = "25.05";
}
