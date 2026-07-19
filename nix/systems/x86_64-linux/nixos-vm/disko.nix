{
  disko.devices.disk.primary = {
    device = "/dev/vda";

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
