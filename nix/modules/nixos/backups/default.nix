{
  config,
  lib,
  pkgs,
  currentUsername,
  ...
}:

let
  cfg = config.backups;
in
{
  options.backups = {
    enable = lib.mkEnableOption "backups (Restic + GDrive)";
    librewolfProfile = lib.mkOption {
      type = lib.types.str;
      description = "LibreWolf profile name to backup";
    };
    flatpakApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "com.core447.StreamController" ];
      description = "List of Flatpak application IDs to backup their ~/.var/app data.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = currentUsername;
      description = "The username to backup files for";
    };
    passwordFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "config.age.secrets.restic-password.path";
      description = "Path to the Restic repository password file";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/mnt/gdrive" = {
      device = "gdrive:";
      fsType = "rclone";
      options = [
        "nodev"
        "nofail"
        "allow_other"
        "args2env"
        "vfs-cache-mode=full"
        "config=/home/${cfg.user}/.config/rclone/rclone.conf"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
        "x-systemd.mount-timeout=30s"
        "_netdev"
      ];
    };

    services.restic.backups.gdrive = {
      repository = "rclone:gdrive:backups/desktop";
      passwordFile = cfg.passwordFile;

      paths =
        (map (p: "/home/${cfg.user}/${p}") [
          "Documents"
          "Pictures"
          "Videos"
          "Music"
          ".librewolf/${cfg.librewolfProfile}/user.js"
          ".librewolf/${cfg.librewolfProfile}/cookies.sqlite"
          ".librewolf/${cfg.librewolfProfile}/cookies.sqlite-wal"
          ".librewolf/${cfg.librewolfProfile}/places.sqlite"
          ".librewolf/${cfg.librewolfProfile}/chrome"
        ])
        ++ [
          "/var/lib/sonarr/.config/NzbDrone/Backups"
          "/var/lib/private/prowlarr/Backups"
        ]
        ++ map (app: "/home/${cfg.user}/.var/app/${app}") cfg.flatpakApps;

      exclude = [
        "*.tmp"
        ".cache"
        "*.log"
        "node_modules"
      ]
      ++ map (p: "/home/${cfg.user}/${p}") [
        "Documents/NVIDIA Nsight Compute"
        "Documents/NVIDIA Nsight Systems"
      ];

      environmentFile = toString (
        pkgs.writeText "gdrive-rclone-env" ''
          RCLONE_CONFIG=/home/${cfg.user}/.config/rclone/rclone.conf
        ''
      );

      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };

      pruneOpts = [
        "--keep-daily 4"
        "--keep-weekly 3"
        "--keep-monthly 2"
      ];

      initialize = true;

      rcloneOptions = {
        drive-use-trash = false;
      };

      createWrapper = true;

      backupPrepareCommand = ''
        echo "Starting Google Drive backup at $(date)"
        echo "Backing up paths: ${pkgs.lib.concatStringsSep ", " config.services.restic.backups.gdrive.paths}"
      '';

      backupCleanupCommand = ''
        echo "Google Drive backup completed at $(date)"
      '';
    };
  };
}
