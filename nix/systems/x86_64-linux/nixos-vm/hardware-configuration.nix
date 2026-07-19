{ lib, pkgs, ... }:

{
  imports = [ ];

  boot = {
    extraModulePackages = [ ];

    initrd = {
      availableKernelModules = [
        "ahci"
        "ata_piix"
        "ehci_pci"
        "mptspi"
        "sd_mod"
        "sr_mod"
        "uhci_hcd"
        "virtio_blk"
        "virtio_pci"
        "virtio_scsi"
      ];

      kernelModules = [ "kvm-amd" ];
    };

    kernel.sysctl = {
      "fs.inotify.max_user_instances" = 2048;
      "fs.inotify.max_user_watches" = 1048576;
    };

    kernelModules = [ ];

    loader = {
      efi.canTouchEfiVariables = true;

      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
        fontSize = 20;
      };
    };
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  swapDevices = [ ];
}
