{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "vmd"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
  ];

  boot.kernelParams = [ 
    "resume_offset=533760"
  ];

  boot.resumeDevice = "/dev/mapper/crypted";

  powerManagement.enable = true;

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576;
    "fs.inotify.max_user_instances" = 2048;
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;

    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
      fontSize = 26;
    };
  };

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
