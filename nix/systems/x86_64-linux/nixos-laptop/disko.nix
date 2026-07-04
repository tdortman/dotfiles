{
  disko.devices.disk.esp = {
    type = "disk";
    device = "/dev/disk/by-uuid/4A77-6910";
    content = {
      type = "filesystem";
      mountpoint = "/boot";
      mountOptions = [ "umask=0077" ];
    };
  };

  disko.devices.disk.main = {
    type = "disk";

    device = "";

    content = {
      type = "luks";
      name = "crypted";

      settings = {
        allowDiscards = true;
      };

      content = {
        type = "btrfs";
        extraArgs = [ "-f" ];

        subvolumes = {
          "/root" = {
            mountpoint = "/";
            mountOptions = [
              "compress=zstd"
              "noatime"
            ];
          };

          "/home" = {
            mountpoint = "/home";
            mountOptions = [
              "compress=zstd"
              "noatime"
            ];
          };

          "/nix" = {
            mountpoint = "/nix";
            mountOptions = [
              "compress=zstd"
              "noatime"
            ];
          };

          "/swap" = {
            mountpoint = "/swap";
            swap.swapfile.size = "18G";
          };
        };
      };
    };
  };
}
