{
  config,
  lib,
  ...
}:
let
  uid = toString config.users.users.${config.common.username}.uid;
in
{
  systemd.services.link-wslg-runtime = lib.mkIf config.wsl.enable {
    description = "Symlink all WSLg runtime files";
    after = [ "user-runtime-dir@${uid}.service" ];
    wants = [ "user-runtime-dir@${uid}.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/wayland-0.lock /run/user/${uid}/wayland-0.lock";

      ExecStartPre = [
        "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/pulse /run/user/${uid}/pulse"
        "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/wayland-0 /run/user/${uid}/wayland-0"
      ];
    };

    enable = true;
  };
}
