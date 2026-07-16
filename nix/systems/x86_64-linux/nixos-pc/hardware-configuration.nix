{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-amd"
    "hid-logitech-dj"
    "zenpower"
    "ntsync"
    "it87"
  ];

  boot.extraModprobeConfig = ''
    options it87 force_id=0x8628
  '';

  boot.blacklistedKernelModules = [ "k10temp" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];

  boot.kernelParams = [
    "resume_offset=33307031"
    "drm.edid_firmware=DP-3:edid/odyssey-g7-8bpc.bin"
    "amd_pstate=active"
    "acpi_enforce_resources=lax"
  ];
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-primary-root";

  powerManagement.enable = true;
  hardware.nvidia.powerManagement.enable = true;

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576;
    "fs.inotify.max_user_instances" = 2048;
  };

  hardware.firmware = [
    (pkgs.runCommand "firmware-custom-edid" { } ''
      mkdir -p $out/lib/firmware/edid/
      cp "${./odyssey-g7-8bpc-edid.bin}" $out/lib/firmware/edid/odyssey-g7-8bpc.bin
    '')
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;

    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
      fontSize = 24;
    };
  };

  users.groups.media = { };

  users.users.sonarr.extraGroups = [ "media" ];
  users.users.qbittorrent.extraGroups = [ "media" ];
  users.users.${config.common.username}.extraGroups = [ "media" ];

  fileSystems."/mnt/shows" = {
    device = "/dev/disk/by-uuid/206C11B36C1184A6";
    fsType = "ntfs3";
    options = [
      "defaults"
      "uid=1000"
      "gid=media"
      "umask=0002"
      "rw"
      "windows_names"
    ];
  };

  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/1260ED5460ED3F5B";
    fsType = "ntfs3";
    options = [
      "defaults"
      "uid=1000"
      "gid=media"
      "umask=0002"
      "rw"
      "discard"
    ];
  };

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
