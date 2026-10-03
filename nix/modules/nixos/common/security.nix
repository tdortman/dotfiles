{ config, pkgs, ... }:

let
  btopPkg = if config.custom.nvidia.driver.enable then pkgs.btop-cuda else pkgs.btop;
in
{
  security = {
    sudo = {
      enable = true;

      extraRules = [
        {
          commands = [ "ALL" ];
          users = [ config.custom.common.username ];
        }
        {
          commands = [
            {
              options = [ "NOPASSWD" ];
              command = "/run/current-system/sw/bin/ip";
            }
          ];

          users = [ config.custom.common.username ];
        }
      ];
    };

    wrappers.btop = {
      capabilities = "cap_perfmon,cap_dac_read_search+ep";
      group = "wheel";
      owner = "root";
      permissions = "u+rx,g+rx,o-rwx";
      source = "${btopPkg}/bin/btop";
    };
  };
}
