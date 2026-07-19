{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot = {
    # Built-in Realtek SD/MMC reader aborts S4 hibernation on this HP Spectre.
    blacklistedKernelModules = [
      "rtsx_pci"
      "rtsx_pci_sdmmc"
    ];

    initrd = {
      availableKernelModules = [
        "nvme"
        "sd_mod"
        "thunderbolt"
        "usb_storage"
        "vmd"
        "xhci_pci"
      ];

      kernelModules = [ ];
    };

    kernel.sysctl = {
      "fs.inotify.max_user_instances" = 2048;
      "fs.inotify.max_user_watches" = 1048576;
    };

    kernelModules = [
      "kvm-intel"
    ];

    kernelParams = [
      "resume_offset=533760"
      "usbcore.autosuspend=-1"
      "xhci_hcd.quirks=0x80"
    ];

    loader = {
      efi.canTouchEfiVariables = true;

      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
        fontSize = 26;
      };
    };

    resumeDevice = "/dev/mapper/crypted";
  };

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  powerManagement = {
    enable = true;

    # Stop and detach hardware paths that abort hibernation on this HP Spectre.
    powerDownCommands = ''
      ${pkgs.systemd}/bin/systemctl stop fwupd.service fprintd.service bluetooth.service 2>/dev/null || true
      ${pkgs.kmod}/bin/modprobe -r btusb 2>/dev/null || true
      for node in XHCI TXHC TDM0 TRP0 TRP1 RP06; do
        ${pkgs.gnugrep}/bin/grep -q "^$node[[:space:]].*\\*enabled" /proc/acpi/wakeup \
          && echo "$node" > /proc/acpi/wakeup || true
      done
      for wakeup in \
        /sys/devices/platform/PNP0C0D:00/power/wakeup \
        /sys/devices/platform/PNP0C0C:00/power/wakeup \
        /sys/devices/pci0000:00/0000:00:15.1/i2c_designware.1/i2c-1/i2c-ELAN072D:00/power/wakeup \
        /sys/devices/pci0000:00/0000:00:1c.0/0000:57:00.0/rtsx_pci_sdmmc.0/power/wakeup \
        /sys/devices/platform/ACPI0003:00/power_supply/ADP1/power/wakeup; do
        test -e "$wakeup" && echo disabled > "$wakeup" || true
      done
      if test -e /sys/bus/pci/drivers/xhci_hcd/unbind \
         && test -e /sys/bus/pci/devices/0000:00:14.0/driver; then
        echo -n 0000:00:14.0 > /sys/bus/pci/drivers/xhci_hcd/unbind || true
      fi
    '';

    resumeCommands = ''
      if test -e /sys/bus/pci/drivers/xhci_hcd/bind \
         && ! test -e /sys/bus/pci/devices/0000:00:14.0/driver; then
        echo -n 0000:00:14.0 > /sys/bus/pci/drivers/xhci_hcd/bind || true
      fi
      ${pkgs.kmod}/bin/modprobe btusb 2>/dev/null || true
      ${pkgs.systemd}/bin/systemctl start bluetooth.service 2>/dev/null || true
    '';
  };
}
