{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";

    device = "/dev/disk/by-uuid/0b989d86-90b8-4cd4-8634-ff21935632d3";

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
