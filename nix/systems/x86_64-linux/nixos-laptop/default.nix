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
    "airvpn-presharedkey".file = inputs.self + /nix/secrets/airvpn-presharedkey.age;
    "airvpn-privatekey".file = inputs.self + /nix/secrets/airvpn-privatekey.age;
    "jgu-vpn-swanctl".file = inputs.self + /nix/secrets/jgu-vpn-swanctl.age;
    "nextdns-resolved.conf".file = inputs.self + /nix/secrets/nextdns-resolved.conf.age;
    "restic-password".file = inputs.self + /nix/secrets/restic-password.age;
  };

  agent-sandbox = {
    enable = true;

    gates = {
      filesystem.enable = true;
      resources.enable = true;
      syscalls.enable = true;
    };

    network.enable = true;

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
          package = agents.droid;
          readwriteDirs = [ "~/.factory" ];
        }
        {
          package = agents.omp;
          readwriteDirs = [ "~/.omp" ];
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

  backups.snapshots.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  environment = {
    systemPackages = with pkgs; [
      (discord.override {
        commandLineArgs = "--enable-blink-features=MiddleClickAutoscroll";
        withVencord = true;
      })
      btrfs-progs
      custom.danbooru-rs
      custom.fluxer
      custom.shiru
      ghostty
      glib
      google-chrome # Used by antigravity
      gvfs
      inputs.agenix.packages."${system}".default
      kdePackages.xdg-desktop-portal-kde
      libnotify
      libreoffice-qt6
      librewolf
      master.antigravity-fhs
      master.code-cursor-fhs
      master.vscode-fhs
      mpv
      nheko
      ntfs3g
      qpwgraph
      samba
      teams-for-linux
      vlc
      xdg-desktop-portal
      xdg-utils
      zed-editor-fhs
    ];

    variables = {
      MOZ_DISABLE_RDD_SANDBOX = 1;
      # Setting gfx.webrender.compositor.force-enabled to true breaks the direct backend
      MOZ_ENABLE_WAYLAND = 1;
      NIXOS_OZONE_WL = "1";
    };
  };

  fingerprint.enable = true;

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

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
      };
    };
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
    hostName = "nixos-laptop";
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
    hostName = "NixOS--Laptop";
  };

  nixpkgs.overlays = [
    # Fingerprint reader needs fork (04f3:0c4c)
    (_: prev: {
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

      libfprint = prev.libfprint.overrideAttrs (oldAttrs: {
        version = "1.94.9"; # fprintd requires libfprint-2.pc to report >= 1.94.9

        src = prev.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          hash = "sha256-uYT1qQK5Hv4AcX9AT9jc36oygiOnpoVh7W4bdsiXWog=";
          owner = "depau";
          repo = "libfprint";
          rev = "elanmoc2-working";
        };

        buildInputs = oldAttrs.buildInputs ++ [ prev.nss ];
        patches = [ ];

        postPatch = (oldAttrs.postPatch or "") + ''
          substituteInPlace meson.build \
            --replace-fail "version: '1.94.7'" "version: '1.94.9'"
        '';
      });
    })
  ];

  onepassword = {
    enable = true;
    user = config.common.username;
  };

  programs = {
    dconf.enable = true;
    mtr.enable = true;
    thunderbird.enable = true;
    virt-manager.enable = true;
  };

  security.rtkit.enable = true;

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

    libinput.enable = true;

    # Let KDE PowerDevil own lid/power policy. logind should only watch the
    # hardware events, not race PowerDevil with a second hibernate request.
    logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandlePowerKey = "ignore";
    };

    pipewire = {
      alsa.enable = true;
      enable = true;

      extraLadspaPackages = [
        pkgs.ladspaPlugins
      ];

      jack.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    printing = {
      drivers = with pkgs; [
        cups-browsed
        cups-filters
      ];

      enable = true;
    };

    ratbagd.enable = true;
    udisks2.enable = true;
  };

  spicetify.enable = true;
  system.stateVersion = "26.11";

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
