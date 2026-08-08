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
    airvpn-presharedkey.file = inputs.self + /nix/secrets/airvpn-presharedkey.age;
    airvpn-privatekey.file = inputs.self + /nix/secrets/airvpn-privatekey.age;
    jgu-vpn-swanctl.file = inputs.self + /nix/secrets/jgu-vpn-swanctl.age;
    "nextdns-resolved.conf".file = inputs.self + /nix/secrets/nextdns-resolved.conf.age;
    restic-password.file = inputs.self + /nix/secrets/restic-password.age;
  };

  agent-sandbox = {
    enable = true;

    gates = {
      filesystem.enable = true;
      resources.enable = true;
      syscalls.enable = true;
    };

    network = {
      enable = true;

      httpProxy = {
        enable = true;
        http3.enable = true;

        websocketHttp11Urls = [
          "https://api.openai.com/v1/live/rtc_*"
        ];
      };
    };

    packages =
      let
        agents = inputs.llm-agents.packages.${system};
      in
      [
        {
          package = agents.codex;
          readwriteDirs = [ "~/.codex" ];
        }
        {
          package = agents.cursor-agent;

          readwriteDirs = [
            "~/.cursor"
            "~/.config/cursor"
            "~/.cache/cursor-compile-cache"
          ];
        }
        {
          package = agents.omp;

          readwriteDirs = [
            "~/.omp"
            "~/.local/state/omp"
          ];
        }
        {
          package = agents.opencode;

          readonlyFiles = [
            "~/.config/cursor/auth.json" # For opencode-cursor
          ];

          readwriteDirs = [
            "~/.config/opencode"
            "~/.local/share/opencode"
            "~/.local/state/opencode"
            "~/.local/share/zoxide"
            "~/.cache/opencode"
            "~/.opencode"

            # cursor-acp
            "~/.opencode-cursor"
            "~/.local/share/cursor-agent"
          ];
        }
      ];

    readonlyDirs = [
      "~/.local/bin"
      "/lib64"
      "/usr/lib"
      "~/.config/agent-sandbox"
    ];

    readonlyFiles = [
      "~/.gitconfig"
      "~/.1password/agent.sock"
      "/usr/bin/env"
    ];

    readwriteDirs = [
      "~/.agents"
    ];

    sudoPolicy = "approve";
  };

  arr-stack.enable = true;

  audio = {
    enable = true;
    input = "alsa_input.usb-Antlion_Audio_Antlion_USB_adapter_20180707-00.mono-fallback";
    inputChannels = "mono";
    output = "alsa_output.usb-Schiit_Audio_Schiit_Modi_Uber-00.analog-stereo";
    mutedInputs = [ "alsa_input.usb-046d_Brio_100_2602ZBR396W8-02.mono-fallback" ];

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

  backups = {
    flatpakApps = [ "com.core447.StreamController" ];
    librewolfProfile = "f9ugjznf.default";

    local = {
      device = "/dev/disk/by-uuid/dfbdb886-3344-4e83-8403-f5ea43187f61";
      enable = true;
      fsType = "btrfs";
      timer = "*-*-* 18:00:00";
    };

    passwordFile = config.age.secrets.restic-password.path;
    remote.enable = true;
    snapshots.enable = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  disableWakeFromHibernate.enable = true;

  environment = {
    systemPackages = with pkgs; [
      (discord.override {
        commandLineArgs = "--enable-blink-features=MiddleClickAutoscroll";
        withVencord = true;
      })
      btrfs-progs
      cuda.llama-cpp
      cuda.lmstudio
      custom.danbooru-rs
      custom.fluxer
      custom.shiru
      dbeaver-bin
      ghidra
      ghostty
      glib
      google-chrome # Used by antigravity
      gvfs
      inputs.agenix.packages."${system}".default
      kdePackages.xdg-desktop-portal-kde
      libnotify
      libratbag
      libreoffice-qt6
      librewolf
      lsfg-vk
      lsfg-vk-ui
      master.antigravity-ide-fhs
      master.code-cursor-fhs
      master.vscode-fhs
      mpv
      nheko
      ntfs3g
      piper
      podman-compose
      samba
      teams-for-linux
      vlc
      winboat
      xdg-desktop-portal
      xdg-utils
      zed-editor-fhs
    ];

    variables = {
      GHIDRA_ROOT = "${pkgs.ghidra}";
      # Hunk inside agent-sandbox
      HUNK_MCP_HOST = "169.254.100.1";
      HUNK_MCP_PORT = 47657;
      HUNK_MCP_UNSAFE_ALLOW_REMOTE = 1;
      MOZ_DISABLE_RDD_SANDBOX = 1;
      MOZ_ENABLE_WAYLAND = 1;
      NIXOS_OZONE_WL = "1";
      # Setting gfx.webrender.compositor.force-enabled to true breaks the direct backend
      NVD_BACKEND = "direct";
    };
  };

  flatpak = {
    enable = true;
    extraOverrides."com.gitbutler.gitbutler".Environment.WEBKIT_DISABLE_DMABUF_RENDERER = "1";

    packages = [
      "com.gitbutler.gitbutler"
      "com.surfshark.Surfshark"
    ];
  };

  gaming.enable = true;

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };

    firmware = with pkgs; [
      rtl8761b-firmware
    ];

    logitech.wireless.enable = true;
    nvidia-container-toolkit.enable = true;
  };

  hdr = {
    enable = true;
    defaultOutput = "DP-3";
    extraScripts = true;
  };

  jgu-vpn = {
    enable = true;

    dnsServers = [
      "134.93.144.2"
      "134.93.144.3"
    ];

    secretsFile = config.age.secrets."jgu-vpn-swanctl".path;
    username = "tdortman@uni-mainz.de";
  };

  kde.enable = true;
  mime.librewolf.enable = true;

  networking = {
    firewall.interfaces.asbx-host.allowedTCPPorts = [ 47657 ];
    hostName = "nixos-pc";
    networkmanager.enable = true;

    wireguard.interfaces = {
      wg0 = {
        allowedIPsAsRoutes = false;
        dynamicEndpointRefreshSeconds = 300;
        ips = [ "10.14.0.2/16" ];

        peers = [
          {
            allowedIPs = [
              "0.0.0.0/0"
              "::/0"
            ];

            endpoint = "de-fra.prod.surfshark.com:51820";
            publicKey = "fJDA+OA6jzQxfRcoHfC27xz7m3C8/590fRjpntzSpGo=";
          }
        ];

        privateKeyFile = "/home/${config.common.username}/.config/wireguard/privatekey";
      };

      wg1 = {
        allowedIPsAsRoutes = false;
        dynamicEndpointRefreshSeconds = 300;
        ips = [ "10.183.233.232/32" ];

        peers = [
          {
            allowedIPs = [
              "0.0.0.0/0"
              "::/0"
            ];

            endpoint = "de3.vpn.airdns.org:51820";
            persistentKeepalive = 15;
            presharedKeyFile = toString config.age.secrets."airvpn-presharedkey".path;
            publicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
          }
        ];

        privateKeyFile = toString config.age.secrets."airvpn-privatekey".path;
      };
    };
  };

  nextdns = {
    enable = true;
    configFile = config.age.secrets."nextdns-resolved.conf".path;
    hostName = "NixOS--PC";
  };

  nvidia = {
    cuda = {
      enable = true;
      nvidia-fs.enable = true;
      packages = pkgs.cudaPackages_13_3;
    };

    driver = {
      enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
  };

  onepassword = {
    enable = true;
    user = config.common.username;
  };

  openrgb.enable = true;

  programs = {
    dconf.enable = true;
    mtr.enable = true;
    streamcontroller.enable = true;
    thunderbird.enable = true;
    virt-manager.enable = true;
  };

  qbittorrent = {
    enable = true;
    port = 32882;

    webui = {
      hashedPassword = "@ByteArray(ld9tpxX1BfxpzgEImGXLJA==:yxC2mw6+EfF14jJNV9ppuS0sqNas7ENWXAccUu+gCVNP0h7NokJA1dgnkoWejmDfp5mq6OEFXEHPGkLJNUZNiw==)";
      port = 8080;
      username = "admin";
    };

    wireguard.interface = "wg0";
  };

  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
      interval = "weekly";
    };

    gvfs.enable = true;

    kmscon.config = {
      font-dpi = 256;
      font-name = "JetBrainsMono Nerd Font Mono";
      font-size = 26;
      hwaccel = true;
    };

    lact.enable = true;
    libinput.enable = true;

    printing = {
      drivers = with pkgs; [
        cups-browsed
        cups-filters
      ];

      enable = true;
    };

    ratbagd.enable = true;

    udev.extraRules = ''
      # StreamController text input
      KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
    '';

    udisks2.enable = true;
  };

  spicetify.enable = true;
  system.stateVersion = "25.05";

  virtualisation = {
    containers.enable = true;

    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
      dockerCompat = true;
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
  };

  vpn-run = {
    enable = true;
    allowedUsers = [ config.common.username ];
    defaultInterface = "wg0";
  };

  xdg.portal.xdgOpenUsePortal = true;
}
