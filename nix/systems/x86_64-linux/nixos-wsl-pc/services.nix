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
    enable = true;
    description = "Symlink all WSLg runtime files";
    wantedBy = [ "multi-user.target" ];
    after = [ "user-runtime-dir@${uid}.service" ];
    wants = [ "user-runtime-dir@${uid}.service" ];

    serviceConfig = {
      ExecStartPre = [
        "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/pulse /run/user/${uid}/pulse"
        "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/wayland-0 /run/user/${uid}/wayland-0"
      ];
      ExecStart = "/run/current-system/sw/bin/ln -sf /mnt/wslg/runtime-dir/wayland-0.lock /run/user/${uid}/wayland-0.lock";
    };
  };
}
