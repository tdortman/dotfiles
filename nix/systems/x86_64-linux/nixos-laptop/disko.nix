{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";

    device = "/dev/disk/by-uuid/cb73055c-201e-45ce-950b-66f5b8e5ad86";

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
