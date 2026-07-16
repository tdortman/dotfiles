{ config, ... }:

{
  security.sudo = {
    enable = true;
    extraRules = [
      {
        users = [ config.common.username ];
        commands = [ "ALL" ];
      }
      {
        users = [ config.common.username ];
        commands = [
          {
            command = "/run/current-system/sw/bin/ip";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
