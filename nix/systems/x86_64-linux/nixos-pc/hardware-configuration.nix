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
    '';

    extraModulePackages = [ config.boot.kernelPackages.zenpower ];

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
      fsType = "ntfs3";
      device = "/dev/disk/by-uuid/1260ED5460ED3F5B";

      options = [
        "defaults"
        "uid=1000"
        "gid=media"
        "umask=0002"
        "rw"
        "discard"
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

  users = {
    groups.media = { };

    users = {
      ${config.common.username}.extraGroups = [ "media" ];
      qbittorrent.extraGroups = [ "media" ];
      sonarr.extraGroups = [ "media" ];
    };
  };
}
