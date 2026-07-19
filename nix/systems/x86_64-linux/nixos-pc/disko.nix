{
  disko.devices.disk.primary = {
    device = "/dev/disk/by-uuid/ea0f1e23-1f8c-4739-815a-025db4591419";

    content = {
      partitions = {
        ESP = {
          size = "1G";

          content = {
            format = "vfat";
            mountOptions = [ "umask=0077" ];
            mountpoint = "/boot";
            type = "filesystem";
          };

          type = "EF00";
        };

        root = {
          size = "100%";

          content = {
            extraArgs = [ "-f" ];

            subvolumes = {
              "/home" = {
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];

                mountpoint = "/home";
              };

              "/nix" = {
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];

                mountpoint = "/nix";
              };

              "/root" = {
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];

                mountpoint = "/";
              };

              "/swap" = {
                mountpoint = "/swap";
                swap.swapfile.size = "70G";
              };
            };

            type = "btrfs";
          };
        };
      };

      type = "gpt";
    };

    type = "disk";
  };
}
