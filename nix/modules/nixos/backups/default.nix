{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.backups;

  # Large, regenerable home content that generally does not belong in backups.
  #
  # Restic patterns without "/" match complete path components at any depth.
  # For case-insensitive cache matching, use commonExtraBackupArgs below instead
  # of putting "**/*cache*" here, because this list is passed as case-sensitive
  # --exclude-file patterns by the NixOS restic module.
  commonExcludes = [
    # Generic temporary files
    "*.tmp"
    "*.temp"
    "*.log"
    "*.bak"
    "*.swp"
    "*~"

    # Generic cache/temp dirs
    ".cache"
    "tmp"
    "temp"

    # Common build/dependency dirs
    "node_modules"
    "target"
    "dist"
    "build"
    ".next"
    ".nuxt"
    ".turbo"
    ".vite"

    # Python
    "__pycache__"
    "*.pyc"
    ".pytest_cache"
    ".mypy_cache"
    ".ruff_cache"
    ".tox"
    ".nox"
    ".venv"
    "venv"

    # Rust / Cargo
    ".rustup"
    ".cargo/registry"
    ".cargo/git"

    # JVM / Gradle
    ".gradle/caches"
    ".gradle/daemon"

    # CMake / Meson
    "CMakeFiles"
    "CMakeCache.txt"
    "cmake-build-*"
    "builddir"
    "meson-private"
    "meson-logs"

    # Linux desktop junk
    ".local/share/Trash"
    ".local/share/recently-used.xbel"
    ".thumbnails"
  ];

  commonExtraBackupArgs = [
    # Exclude dirs marked with CACHEDIR.TAG.
    "--exclude-caches"

    # Manual opt-out marker for arbitrary large/regenerable dirs.
    "--exclude-if-present=.nobackup"

    # Case-insensitive catch-all for Cache, cache, Code Cache, GPUCache, etc.
    "--iexclude=**/*cache*"
  ];

  # snapper config name, derived from the snapshotted subvolume path.
  snapName = lib.last (lib.splitString "/" cfg.snapshots.subvolume);
in
{
  options.backups = {
    user = lib.mkOption {
      type = lib.types.str;
      default = config.common.username;
      description = "The username to back up files for";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "config.age.secrets.restic-password.path";
      description = "Path to the Restic repository password file";
    };

    remote = {
      enable = lib.mkEnableOption "Google Drive Restic backup of selected home data";
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

    local = {
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

  config = lib.mkMerge [
    (lib.mkIf cfg.remote.enable {
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

        extraBackupArgs = commonExtraBackupArgs;

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
    })

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

    (lib.mkIf cfg.local.enable {
      # ---- Local Restic backup to a dedicated disk ----
      fileSystems.${cfg.local.mountPoint} = {
        device = cfg.local.device;
        fsType = cfg.local.fsType;
        options = [
          "defaults"
          "noatime"
          "nofail"
        ];
      };

      services.restic.backups.local = {
        repository = "${cfg.local.mountPoint}/restic";
        inherit (cfg) passwordFile;

        paths = [ cfg.snapshots.subvolume ];

        exclude = commonExcludes ++ [
          ".snapshots"

          "/home/${cfg.user}/Downloads"
          "/home/${cfg.user}/3rd-party"
          "/home/${cfg.user}/.lmstudio/models"

          # Exclude any directory named "data" below ~/projects, but not arbitrary
          # "data" directories elsewhere in the home directory.
          "/home/${cfg.user}/projects/data"
          "/home/${cfg.user}/projects/**/data"

          # Large, reinstallable game content.
          "/home/${cfg.user}/.local/share/Steam/steamapps"
        ];

        extraBackupArgs = commonExtraBackupArgs;

        timerConfig = {
          OnCalendar = cfg.local.timer;
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
      systemd.services.restic-backups-local.unitConfig.RequiresMountsFor = cfg.local.mountPoint;
    })
  ];
}
