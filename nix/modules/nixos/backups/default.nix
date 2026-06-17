{
  config,
  lib,
  pkgs,
  currentUsername,
  ...
}:

let
  cfg = config.backups;

  # Large, regenerable home content that never belongs in any backup.
  # Bare names match any path component at any depth in restic's matcher,
  # so every target below inherits the same exclusions.
  commonExcludes = [
    "*.tmp"
    "*.log"
    ".cache"
    "node_modules"
    "target"
    "Downloads"
    "data"
    "models"
    "3rd-party"
    ".rustup"
  ];

  # snapper config name, derived from the snapshotted subvolume path.
  snapName = lib.last (lib.splitString "/" cfg.snapshots.subvolume);
in
{
  options.backups = {
    enable = lib.mkEnableOption "home backups (Restic to GDrive, with optional local disk and btrfs snapshots)";

    user = lib.mkOption {
      type = lib.types.str;
      default = currentUsername;
      description = "The username to back up files for";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "config.age.secrets.restic-password.path";
      description = "Path to the Restic repository password file";
    };

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

    snapshots = {
      enable = lib.mkEnableOption "automatic btrfs snapshots of the home subvolume via snapper";

      subvolume = lib.mkOption {
        type = lib.types.str;
        default = "/home";
        description = "Mounted btrfs subvolume to snapshot.";
      };
    };

    localBackup = {
      enable = lib.mkEnableOption "a local Restic backup of the home subvolume to a disk";

      device = lib.mkOption {
        type = lib.types.str;
        example = "/dev/disk/by-uuid/...";
        description = "Device path of the backup disk, mounted at mountPoint.";
      };

      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        description = "Filesystem type of the backup disk.";
      };

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/backup";
        description = "Mountpoint for the local backup disk.";
      };
      timer = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = ''
          systemd OnCalendar expression for the local backup timer
          (e.g. "*-*-* 18:00:00" for daily at 18:00).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # ---- Google Drive backup (Restic over rclone) ----
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
          inherit (cfg) passwordFile;

          paths =
            (map (p: "/home/${cfg.user}/${p}") [
              "Documents"
              "Pictures"
              "Videos"
              "Music"
              ".librewolf/${cfg.librewolfProfile}"
            ])
            ++ [
              "/var/lib/sonarr/.config/NzbDrone/Backups"
              "/var/lib/private/prowlarr/Backups"
            ]
            ++ map (app: "/home/${cfg.user}/.var/app/${app}") cfg.flatpakApps;

          exclude =
            commonExcludes
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
      }

      (lib.mkIf cfg.snapshots.enable {
        # ---- Local btrfs snapshots of /home via snapper ----
        services.snapper.configs.${snapName} = {
          SUBVOLUME = cfg.snapshots.subvolume;
          FSTYPE = "btrfs";
          ALLOW_USERS = [ cfg.user ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_LIMIT_HOURLY = "7";
          TIMELINE_LIMIT_DAILY = "7";
        };

        # The NixOS snapper module only writes the config and timers. It does not
        # create the .snapshots subvolume that snapper needs, so create it once
        # before the timeline service is allowed to run.
        systemd.services."snapper-${snapName}-init" = {
          description = "Create btrfs .snapshots subvolume for snapper on ${cfg.snapshots.subvolume}";
          wantedBy = [ "multi-user.target" ];
          requires = [ "local-fs.target" ];
          after = [ "local-fs.target" ];
          before = [
            "snapper-timeline.service"
            "snapper-cleanup.service"
          ];
          unitConfig.ConditionPathExists = "!${cfg.snapshots.subvolume}/.snapshots";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.btrfs-progs}/bin/btrfs subvolume create ${cfg.snapshots.subvolume}/.snapshots";
          };
        };
      })

      (lib.mkIf cfg.localBackup.enable {
        # ---- Local Restic backup to a dedicated disk ----
        fileSystems.${cfg.localBackup.mountPoint} = {
          device = cfg.localBackup.device;
          fsType = cfg.localBackup.fsType;
          options = [
            "defaults"
            "noatime"
            "nofail"
          ];
        };

        services.restic.backups.local = {
          repository = "${cfg.localBackup.mountPoint}/restic";
          inherit (cfg) passwordFile;

          paths = [ cfg.snapshots.subvolume ];

          exclude = commonExcludes ++ [
            ".snapshots"
            ".local/share/Trash"
            "/home/${cfg.user}/.local/share/Steam/steamapps"
          ];

          timerConfig = {
            OnCalendar = cfg.localBackup.timer;
            Persistent = true;
          };

          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 2"
          ];

          initialize = true;
          createWrapper = true;
        };

        # Never let restic write into a stale mountpoint on the root filesystem:
        # skip the backup entirely when the disk is not mounted.
        systemd.services.restic-backups-local.unitConfig.RequiresMountsFor = cfg.localBackup.mountPoint;
      })
    ]
  );
}
