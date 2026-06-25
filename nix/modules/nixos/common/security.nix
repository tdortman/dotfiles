{ currentUsername, ... }:

{
  security.sudo = {
    enable = true;
    extraRules = [
      {
        users = [ currentUsername ];
        commands = [ "ALL" ];
      }
      {
        users = [ currentUsername ];
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
