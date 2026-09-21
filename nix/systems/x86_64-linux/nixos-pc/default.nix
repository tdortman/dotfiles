{
  config,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:

{
  imports = [
    "${inputs.nixpkgs-plasma-beta}/nixos/modules/services/desktop-managers/plasma6.nix"
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

      loopback.tcpPorts = [
        3080 # DSH
        47657 # hunk
      ];
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
          package = agents.dsh;

          readwriteDirs = [
            "~/.dsh"
            "~/.local/share/ponytail/skills"
          ];
        }
        {
          package = agents.omp;

          readwriteDirs = [
            "~/.omp"
            "~/.cache/omp"
            "~/.local/state/omp"
            "~/.local/share/omp"
          ];
        }
        {
          package = agents.opencode2;

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

    policy.dbus.enable = true;

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

      Music.appNames = [
        "foobar2000 Application"
        "spotify"
      ];

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

  boot = {
    initrd.kernelModules = [ "i915" ];
    kernelPackages = pkgs.linuxPackages_latest;
  };

  disableWakeFromHibernate.enable = true;
  disabledModules = [ "services/desktop-managers/plasma6.nix" ];

  display-layout = {
    enable = true;
    ddc.enable = true;

    layouts = [
      {
        disabledOutputs = [ "DP-4" ];
        name = "intel";

        outputs = [
          {
            input = 15;
            output = "DP-1";
            gpu = "0000:07:00.0";
            primary = true;
            scale = 1.3;
          }
          {
            output = "DP-2";
            gpu = "0000:07:00.0";
          }
        ];
      }
      {
        disabledOutputs = [ "DP-4" ];
        name = "nvidia";

        outputs = [
          {
            input = 17;
            output = "HDMI-A-5";

            ddcControl = {
              output = "DP-1";
              gpu = "0000:07:00.0";
            };

            gpu = "0000:0d:00.0";
            primary = true;
            scale = 1.0;
          }
          {
            output = "DP-2";
            gpu = "0000:07:00.0";
          }
        ];
      }
    ];

    loginLayout = "intel";
  };

  environment = {
    sessionVariables = {
      CARGO_BUILD_JOBS = 22;
      CARGO_MAKEFLAGS = "-j 22";
      CMAKE_CUDA_COMPILER_LAUNCHER = lib.getExe pkgs.kache;
      CMAKE_CXX_COMPILER_LAUNCHER = lib.getExe pkgs.kache;
      CMAKE_C_COMPILER_LAUNCHER = lib.getExe pkgs.kache;
      CODEX_CLI_PATH = "/run/current-system/sw/bin/codex";
      GHIDRA_ROOT = "${pkgs.ghidra}";
      KACHE_FALLBACK = lib.getExe pkgs.sccache;
      # Stable PCI selection keeps the desktop on Arc regardless of DRM enumeration.
      KWIN_DRM_DEVICES = "/dev/dri/intel-arc:/dev/dri/nvidia-gaming";
      MAKEFLAGS = "-j 22";
      MOZ_ENABLE_WAYLAND = 1;
      NINJAFLAGS = "-j 22";
      NIXOS_OZONE_WL = "1";
      RUSTC_WRAPPER = lib.getExe pkgs.kache;
      SCCACHE_CACHE_SIZE = "50G";
      SCCACHE_DIR = "$HOME/.cache/sccache";
    };

    systemPackages =
      with pkgs;
      map
        (
          { flags, name }:
          writeShellApplication {
            inherit name;

            runtimeInputs = [
              coreutils
              gamescope
            ];

            text = ''
              if [[ $# -eq 0 ]]; then
                echo 'Usage: ${name} command [args...]' >&2
                exit 2
              fi

              unset PROTON_ENABLE_WAYLAND DISABLE_GAMESCOPE_WSI ENABLE_GAMESCOPE_WSI

              export VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
              exec gamescope --backend wayland --force-composition --force-windows-fullscreen \
                -w 3840 -h 2160 -W 3840 -H 2160 -f --prefer-vk-device 10de:2c05 \
                ${flags} -- env -u WAYLAND_DEBUG \
                ENABLE_GAMESCOPE_WSI=1 PROTON_ENABLE_HDR=1 "$@"
            '';
          }
        )
        [
          {
            flags = "";
            name = "gamescope-game-sdr";
          }
          {
            flags = "--hdr-enabled --mangoapp";
            name = "gamescope-game-hdr-mango";
          }
          {
            flags = "--hdr-enabled";
            name = "gamescope-game-hdr";
          }
          {
            flags = "--mangoapp";
            name = "gamescope-game-sdr-mango";
          }
        ]
      ++ [
        (discord.override {
          commandLineArgs = "--enable-blink-features=MiddleClickAutoscroll";
          withVencord = true;
        })
        btrfs-progs
        # cuda.llama-cpp
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
        inputs.codex-desktop-linux.packages.${system}.codex-desktop-maximal-directory-watch
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
      ]
      ++ (with inputs.llm-agents.packages.${system}; [
        (t3code.override { providerPackages = [ ]; }).desktop
      ]);
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
      input.General.UserspaceHID = false;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };

    firmware = with pkgs; [
      rtl8761b-firmware
    ];

    logitech.wireless.enable = true;

    nvidia.prime = {
      intelBusId = "PCI:7:0:0";
      nvidiaBusId = "PCI:13:0:0";

      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
    };

    nvidia-container-toolkit.enable = true;
  };

  hdr = {
    enable = true;
    extraScripts = true;
  };

  intel.enable = true;

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

  nix.settings.cores = 22;

  nixpkgs.overlays = lib.mkBefore [
    (final: prev: {
      kdePackages =
        (import inputs.nixpkgs-plasma-beta {
          inherit (prev) config;
          inherit system;
        }).kdePackages.overrideScope
          (
            kfinal: kprev: {
              ktnef = kprev.ktnef.overrideAttrs (oldAttrs: {
                buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ kfinal.kcalutils ];
              });

              kwin = kprev.kwin.overrideAttrs (oldAttrs: {
                patches = (oldAttrs.patches or [ ]) ++ [ ./kwin-drm-color-pipeline.patch ];
              });
            }
          );

      # `libreoffice-qt` is defined through whatever `kdePackages` resolves to,
      # so the beta scope drags in that snapshot's whole package set (boost,
      # openssl, qtbase). Those builds miss the binary cache and LibreOffice
      # compiles from source. Build it from the unmodified package set instead.
      libreoffice-qt =
        (import prev.path {
          inherit system;
          inherit (prev) config;
        }).libreoffice-qt;
    })
  ];

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
      # Colon-free aliases avoid escaping PCI paths in KWin's device list.
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:07:00.0", SYMLINK+="dri/intel-arc"
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:0d:00.0", SYMLINK+="dri/nvidia-gaming"

      # StreamController text input
      KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
    '';

    udisks2.enable = true;
  };

  services.kache = {
    enable = true;
    rustcWrapper = true;
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
