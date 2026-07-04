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
  spicetify.enable = true;
  fingerprint.enable = true;

  nixpkgs.overlays = [
    # Fingerprint reader needs fork (04f3:0c4c)
    (_: prev: {
      libfprint = prev.libfprint.overrideAttrs (oldAttrs: {
        version = "1.94.9"; # fprintd requires libfprint-2.pc to report >= 1.94.9
        src = prev.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "depau";
          repo = "libfprint";
          rev = "elanmoc2-working";
          hash = "sha256-uYT1qQK5Hv4AcX9AT9jc36oygiOnpoVh7W4bdsiXWog=";
        };
        patches = [ ];
        buildInputs = oldAttrs.buildInputs ++ [ prev.nss ];
        postPatch = (oldAttrs.postPatch or "") + ''
          substituteInPlace meson.build \
            --replace-fail "version: '1.94.7'" "version: '1.94.9'"
        '';
      });

      fprintd = prev.fprintd.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          (prev.writeText "fprintd-optional-too-fast-retry.patch" (
            builtins.concatStringsSep "\n" [
              "diff --git a/src/device.c b/src/device.c"
              "--- a/src/device.c"
              "+++ b/src/device.c"
              "@@ -602,8 +602,10 @@ verify_result_to_name (FpDevice *rdev, gboolean match, GError *error)"
              "         case FP_DEVICE_RETRY_REMOVE_FINGER:"
              "           return \"verify-remove-and-retry\";"
              ""
              "+#ifdef FP_DEVICE_RETRY_TOO_FAST"
              "         case FP_DEVICE_RETRY_TOO_FAST:"
              "           return \"verify-too-fast\";"
              "+#endif"
              ""
              "         default:"
              "           return \"verify-retry-scan\";"
              "@@ -654,8 +656,10 @@ enroll_result_to_name (gboolean completed, gboolean enrolled, GError *error)"
              "         case FP_DEVICE_RETRY_REMOVE_FINGER:"
              "           return \"enroll-remove-and-retry\";"
              ""
              "+#ifdef FP_DEVICE_RETRY_TOO_FAST"
              "         case FP_DEVICE_RETRY_TOO_FAST:"
              "           return \"enroll-too-fast\";"
              "+#endif"
              ""
              "         default:"
              "           return \"enroll-retry-scan\";"
              ""
            ]
          ))
        ];
      });
    })
  ];

  onepassword = {
    enable = true;
    user = currentUsername;
  };

  backups.snapshots.enable = true;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;

    extraLadspaPackages = [
      pkgs.ladspaPlugins
    ];
  };

  nextdns = {
    enable = true;
    configFile = config.age.secrets."nextdns-resolved.conf".path;
    hostName = "NixOS--Laptop";
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
    gates = {
      filesystem.enable = true;
      resources.enable = true;
      syscalls.enable = true;
    };
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
            "~/.cache/cursor-compile-cache"
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
            "~/.local/state/opencode"
            "~/.local/share/zoxide"
            "~/.cache/opencode"
            "~/.opencode"

            # cursor-acp
            "~/.opencode-cursor"
            "~/.local/share/cursor-agent"
          ];
          readonlyFiles = [
            "~/.config/cursor/auth.json" # For opencode-cursor
          ];
        }
        {
          package = agents.droid;
          readwriteDirs = [ "~/.factory" ];
        }
      ];
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

  networking.hostName = "nixos-laptop";

  mime.librewolf.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  services.libinput.enable = true;

  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  services.ratbagd.enable = true;

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  programs.dconf.enable = true;

  programs.thunderbird.enable = true;

  environment.systemPackages = with pkgs; [
    ntfs3g
    ghostty
    btrfs-progs
    mpv
    librewolf

    gvfs
    samba
    glib
    qpwgraph

    inputs.agenix.packages."${system}".default

    vlc
    libnotify
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

  xdg.portal.xdgOpenUsePortal = true;

  environment.variables = {
    NIXOS_OZONE_WL = "1";

    # Setting gfx.webrender.compositor.force-enabled to true breaks the direct backend
    MOZ_ENABLE_WAYLAND = 1;
    MOZ_DISABLE_RDD_SANDBOX = 1;
  };

  programs.mtr.enable = true;
  system.stateVersion = "26.11";
}
