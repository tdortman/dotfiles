{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.disableWakeFromHibernate;
  script = pkgs.writeShellScript "disable_wakeup.sh" ''
    case "$1" in
      pre)
        # Disable the `power/wakeup` flag for devices where it exists.
        for f in /sys/bus/usb/devices/*/power/wakeup; do
          [ -e "$f" ] || continue
          echo disabled > "$f" 2>/dev/null || true
        done
        ;;
      post)
        # Re-enable those wakeup flags on resume
        for f in /sys/bus/usb/devices/*/power/wakeup; do
          [ -e "$f" ] || continue
          echo enabled > "$f" 2>/dev/null || true
        done
        ;;
      *)
        ;;
    esac
  '';

in
{
  options.disableWakeFromHibernate = {
    enable = lib.mkEnableOption "service to disable wakeup from hibernate for usb devices";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."systemd/system-sleep/disable_wakeup.sh".source = script;
  };
}
