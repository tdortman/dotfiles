{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-INTEL_HBRPEKNX0202AH_BTTE04330BBY512B-1";

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

        luks = {
          size = "350G";

          content = {
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
                  swap.swapfile.size = "18G";
                };
              };

              type = "btrfs";
            };

            name = "crypted";
            settings.allowDiscards = true;
            type = "luks";
          };
        };
      };

      type = "gpt";
    };

    type = "disk";
  };
}
