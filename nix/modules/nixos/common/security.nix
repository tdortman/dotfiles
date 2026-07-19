{ config, ... }:

{
  security.sudo = {
    enable = true;

    extraRules = [
      {
        commands = [ "ALL" ];
        users = [ config.common.username ];
      }
      {
        commands = [
          {
            options = [ "NOPASSWD" ];
            command = "/run/current-system/sw/bin/ip";
          }
        ];

        users = [ config.common.username ];
      }
    ];
  };
}
