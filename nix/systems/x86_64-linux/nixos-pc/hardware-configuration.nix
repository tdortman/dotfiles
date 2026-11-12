{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot = {
    blacklistedKernelModules = [ "k10temp" ];

    extraModprobeConfig = ''
      options it87 force_id=0x8628
      options nvidia_modeset frl_train_backoff_ms=500 frl_caps_retention=1
    '';

    # ponytail: local fix for NixOS/nixpkgs#575192 (zenpower installs its .ko
    # by hand, so kmodigest never writes the .ko.cer aggregateModules needs);
    # drop once nixpkgs routes zenpower through modules_install.
    extraModulePackages = [
      (config.boot.kernelPackages.zenpower.overrideAttrs (old: {
        installFlags = [
          "-C"
          "${config.boot.kernelPackages.kernel.dev}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/build"
          "M=$(PWD)"
          "INSTALL_MOD_PATH=${placeholder "out"}"
          "INSTALL_MOD_DIR=kernel/drivers/hwmon/zenpower"
          "DEPMOD=true"
        ];

        installPhase = null;
        installTargets = [ "modules_install" ];
        makeFlags = config.boot.kernelPackages.kernelModuleMakeFlags ++ old.makeFlags;
      }))
    ];

    initrd = {
      availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "usb_storage"
        "usbhid"
        "xhci_pci"
      ];

      kernelModules = [ ];
    };

    kernel.sysctl = {
      "fs.inotify.max_user_instances" = 2048;
      "fs.inotify.max_user_watches" = 1048576;
    };

    kernelModules = [
      "hid-logitech-dj"
      "it87"
      "kvm-amd"
      "ntsync"
      "zenpower"
    ];

    kernelParams = [
      "resume_offset=33307031"
      "amd_pstate=active"
      "acpi_enforce_resources=lax"
    ];

    loader = {
      efi.canTouchEfiVariables = true;

      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
        fontSize = 24;
      };
    };

    resumeDevice = "/dev/disk/by-partlabel/disk-primary-root";
  };

  fileSystems = {
    "/mnt/games" = {
      fsType = "btrfs";
      device = "/dev/disk/by-uuid/d39ddc07-3c9c-4b41-950b-55f39131b1c5";

      options = [
        "defaults"
        "noatime"
        "nofail"
      ];
    };

    "/mnt/shows" = {
      fsType = "ntfs3";
      device = "/dev/disk/by-uuid/206C11B36C1184A6";

      options = [
        "defaults"
        "uid=1000"
        "gid=media"
        "umask=0002"
        "rw"
        "windows_names"
        "nofail" # don't block the boot if the volume is unusable
        "force" # ntfs3 refuses rw mount while the dirty flag is set (hard reset)
      ];
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    display = {
      edid.packages = [
        (pkgs.runCommand "firmware-custom-edid" { } ''
          mkdir -p $out/lib/firmware/edid/
          cp "${./odyssey-g7-8bpc-edid.bin}" $out/lib/firmware/edid/odyssey-g7-8bpc.bin
        '')
      ];

      outputs.DP-2.edid = "odyssey-g7-8bpc.bin";
    };

    nvidia.powerManagement.enable = true;
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.enable = true;

  systemd.services.nvidia-power-limit = {
    description = "Set the RTX 5070 Ti power limit to 250 W";

    after = [
      "nvidia-resume.service"
      "systemd-hibernate.service"
      "systemd-hybrid-sleep.service"
      "systemd-modules-load.service"
      "systemd-suspend-then-hibernate.service"
      "systemd-suspend.service"
    ];

    wantedBy = [
      "hibernate.target"
      "hybrid-sleep.target"
      "multi-user.target"
      "suspend-then-hibernate.target"
      "suspend.target"
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi --id=0000:0d:00.0 --power-limit=250";
    };
  };
  systemd.services.intel-arc-power-profile = {
    description = "Set Intel Arc GPU SLPC power-saving profile and frequency caps";

    after = [
      "systemd-hibernate.service"
      "systemd-hybrid-sleep.service"
      "systemd-modules-load.service"
      "systemd-suspend-then-hibernate.service"
      "systemd-suspend.service"
    ];

    wantedBy = [
      "hibernate.target"
      "hybrid-sleep.target"
      "multi-user.target"
      "suspend-then-hibernate.target"
      "suspend.target"
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "intel-arc-power-profile" ''
        for card in /sys/class/drm/card*; do
          if [ -d "$card/gt/gt0" ] && [ "$(${pkgs.coreutils}/bin/cat "$card/device/vendor" 2>/dev/null)" = "0x8086" ]; then
            echo power_saving > "$card/gt/gt0/slpc_power_profile" 2>/dev/null || true
            echo 1000 > "$card/gt/gt0/rps_boost_freq_mhz" 2>/dev/null || true
            echo 1400 > "$card/gt/gt0/rps_max_freq_mhz" 2>/dev/null || true
            echo 1 > "$card/gt/gt0/slpc_ignore_eff_freq" 2>/dev/null || true
          fi
        done
      '';
    };
  };

  users = {
    groups.media = { };

    users = {
      ${config.custom.common.username}.extraGroups = [ "media" ];
      qbittorrent.extraGroups = [ "media" ];
      sonarr.extraGroups = [ "media" ];
    };
  };
}
