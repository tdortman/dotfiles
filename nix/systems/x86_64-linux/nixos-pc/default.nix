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
    ../../../common
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
  };

  onepassword = {
    enable = true;
    user = currentUsername;
  };

  audio = {
    enable = true;
    input = "alsa_input.pci-0000_0b_00.4.analog-stereo";
    output = "alsa_output.usb-Schiit_Audio_Schiit_Modi_Uber-00.analog-stereo";

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
    "restic-password".file = ../../../secrets/restic-password.age;
    "nextdns-resolved.conf".file = ../../../secrets/nextdns-resolved.conf.age;
    "airvpn-privatekey".file = ../../../secrets/airvpn-privatekey.age;
    "airvpn-presharedkey".file = ../../../secrets/airvpn-presharedkey.age;
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

  services.sonarr = {
    enable = true;
    openFirewall = true;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  services.flaresolverr = {
    enable = true;
    openFirewall = true;
  };

  programs.streamcontroller.enable = true;

  services.udev.extraRules = ''
    # StreamController text input
    KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
  '';

  virtualisation.docker.enable = true;
  hardware.nvidia-container-toolkit.enable = true;

  services.flatpak = {
    enable = true;
    packages = [
      "com.surfshark.Surfshark"
      "com.gitbutler.gitbutler"
    ];
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
    overrides = {
      global = {
        Context = {
          filesystems = [
            "xdg-config/fontconfig:ro"
            "xdg-config/gtkrc:ro"
            "xdg-config/gtkrc-2.0:ro"
            "xdg-config/gtk-2.0:ro"
            "xdg-config/gtk-3.0:ro"
            "xdg-config/gtk-4.0:ro"
            "xdg-data/themes:ro"
            "xdg-data/icons:ro"
          ];
        };
        Environment = {
          GTK_THEME = "Breeze";
        };
      };
      "com.gitbutler.gitbutler" = {
        Environment = {
          WEBKIT_DISABLE_DMABUF_RENDERER = "1";
        };
      };
    };

  };

  networking.hostName = "nixos-pc";

  xdg.mime.defaultApplications = {
    "text/html" = "librewolf.desktop";
    "x-scheme-handler/http" = "librewolf.desktop";
    "x-scheme-handler/https" = "librewolf.desktop";
    "x-scheme-handler/about" = "librewolf.desktop";
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.networkmanager = {
    enable = true;
    plugins = [
      pkgs.networkmanager-strongswan
    ];
  };

  environment.etc."strongswan.conf".text = ''
    charon-nm { plugins { eap-peap { load = no } } }
  '';

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
  services.gnome.gnome-keyring.enable = true;

  environment.systemPackages = with pkgs; [
    ntfs3g
    ghostty
    vscode-fhs
    zed-editor-fhs
    btrfs-progs
    mpv
    librewolf
    antigravity-fhs
    google-chrome # Used by antigravity

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

    # Bluetooth Dongle
    rtl8761b-firmware

    (discord.override {
      withVencord = true;
      commandLineArgs = "--enable-blink-features=MiddleClickAutoscroll";
    })

    master.opencode
    github-copilot-cli
    master.codex
    custom.droid

    custom.danbooru-rs
    custom.shiru
    custom.fluxer
  ];

  hardware.logitech.wireless.enable = true;

  xdg.portal.xdgOpenUsePortal = true;

  environment.shellAliases = {
    agy = "(pkill -f -9 antigravity || true) && ${pkgs.antigravity-fhs}/bin/antigravity";
  };

  environment.variables = {
    BROWSER = "${pkgs.librewolf}/bin/librewolf";
    DEFAULT_BROWSER = "${pkgs.librewolf}/bin/librewolf";

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
