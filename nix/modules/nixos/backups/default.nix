{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.backups;
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
  notifyOnFailure = "backup-failure-notify@%n.service";
  # snapper config name, derived from the snapshotted subvolume path.
  snapName = lib.last (lib.splitString "/" cfg.snapshots.subvolume);
  # Btrfs snapshots stop at subvolume boundaries, so subvolumes below
  # snapshots.projectsDir are empty directories in the snapper snapshots. After
  # each timeline run, snapshot them into ~/.snapshots/<snapper number>/ and drop
  # numbers that snapper has cleaned up, so they follow the same retention.
  snapshotProjects = pkgs.writeShellApplication {
    name = "snapper-projects";

    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.fd
    ];

    text = ''
      root=${cfg.snapshots.projectsDir}
      snapper_dir=${cfg.snapshots.subvolume}/.snapshots
      out=/home/${cfg.user}/.snapshots

      install -d -m 700 -o ${cfg.user} "$out"

      # Each number is one subvolume holding that run's project snapshots.
      # Anything not named after a live snapper snapshot, including an
      # interrupted "partial" run, is removed.
      for dir in "$out"/*/; do
        dir=''${dir%/}
        [[ -d $dir ]] || continue
        [[ -d $snapper_dir/$(basename "$dir") ]] && continue
        btrfs subvolume delete --recursive "$dir"
      done

      latest=$(fd --no-ignore --max-depth 1 --type d '^[0-9]+$' "$snapper_dir" --format '{/}' | sort -n | tail -n 1)
      [[ -n $latest && ! -e $out/$latest ]] || exit 0

      # Subvolume roots are always inode 256. fd skips hidden and gitignored
      # directories such as .git and target. Sorting puts every subvolume
      # after the subvolumes containing it.
      mapfile -d "" -t entries < <(
        fd --type d . "$root" --exec-batch stat --printf '%i %n\0' | LC_ALL=C sort -z
      )
      wait $!

      btrfs subvolume create "$out/partial"
      snapshots=()
      for entry in "''${entries[@]}"; do
        [[ $entry == "256 "* ]] || continue
        subvol=''${entry#256 }
        dest=$out/partial/''${subvol#"$root"/}
        # A nested subvolume shows up as an empty directory in its parent's
        # snapshot; replace that with the nested snapshot.
        if [[ -d $dest ]]; then
          rmdir "$dest"
        fi
        mkdir -p "$(dirname "$dest")"
        btrfs subvolume snapshot "$subvol" "$dest"
        snapshots+=("$dest")
      done

      # Read-only only once every nested snapshot is in place.
      for dest in "''${snapshots[@]}"; do
        btrfs property set -ts "$dest" ro true
      done

      mv "$out/partial" "$out/$latest"
    '';
  };
  # The restic module only unlocks after a successful backup, so a lock left by
  # an interrupted prune makes every later run fail before it gets there.
  # `unlock` removes stale locks only, so live runs are unaffected.
  unlockStale = "${lib.getExe pkgs.restic} unlock";
in
{
  options.custom.backups = {
    flatpakApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "com.core447.StreamController" ];
      default = [ ];
      description = "List of Flatpak application IDs to backup their ~/.var/app data.";
    };

    librewolfProfile = lib.mkOption {
      type = lib.types.str;
      description = "LibreWolf profile name to backup";
    };

    local = {
      device = lib.mkOption {
        type = lib.types.str;
        example = "/dev/disk/by-uuid/...";
        description = "Device path of the backup disk, mounted at mountPoint.";
      };

      enable = lib.mkEnableOption "a local Restic backup of the home subvolume to a disk";

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

    passwordFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "config.age.secrets.restic-password.path";
      description = "Path to the Restic repository password file";
    };

    remote.enable = lib.mkEnableOption "Google Drive Restic backup of selected home data";

    snapshots = {
      enable = lib.mkEnableOption "automatic btrfs snapshots of the home subvolume via snapper";

      projectsDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}/Projects";
        defaultText = lib.literalExpression ''"/home/''${config.custom.backups.user}/Projects"'';

        description = ''
          Directory whose btrfs subvolumes, at any depth, are snapshotted into
          ~/.snapshots alongside each snapper timeline snapshot. Must be on the
          same btrfs filesystem as the home directory.
        '';
      };

      subvolume = lib.mkOption {
        type = lib.types.str;
        default = "/home";
        description = "Mounted btrfs subvolume to snapshot.";
      };
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.custom.common.username;
      description = "The username to back up files for";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.remote.enable {
      # ---- Google Drive backup (Restic over rclone) ----
      fileSystems."/mnt/gdrive" = {
        fsType = "rclone";
        device = "gdrive:";

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
        inherit (cfg) passwordFile;

        backupCleanupCommand = ''
          echo "Google Drive backup finished at $(date): $SERVICE_RESULT"
        '';

        backupPrepareCommand = ''
          echo "Starting Google Drive backup at $(date)"
          echo "Backing up paths: ${pkgs.lib.concatStringsSep ", " config.services.restic.backups.gdrive.paths}"
          ${unlockStale}
        '';

        createWrapper = true;

        environmentFile = toString (
          pkgs.writeText "gdrive-rclone-env" ''
            RCLONE_CONFIG=/home/${cfg.user}/.config/rclone/rclone.conf
          ''
        );

        exclude =
          commonExcludes
          ++ map (p: "/home/${cfg.user}/${p}") [
            "Documents/NVIDIA Nsight Compute"
            "Documents/NVIDIA Nsight Systems"
          ];

        extraBackupArgs = commonExtraBackupArgs;
        initialize = true;

        paths =
          (map (p: "/home/${cfg.user}/${p}") [
            ".librewolf/${cfg.librewolfProfile}"
            "Documents"
            "Music"
            "Pictures"
            "Videos"
          ])
          ++ [
            "/var/lib/private/prowlarr/Backups"
            "/var/lib/sonarr/.config/NzbDrone/Backups"
          ]
          ++ map (app: "/home/${cfg.user}/.var/app/${app}") cfg.flatpakApps;

        pruneOpts = [
          "--keep-daily 4"
          "--keep-weekly 3"
          "--keep-monthly 2"
        ];

        rcloneOptions.drive-use-trash = false;
        repository = "rclone:gdrive:backups/desktop";

        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

      systemd.services.restic-backups-gdrive.onFailure = [ notifyOnFailure ];
    })

    (lib.mkIf cfg.snapshots.enable {
      # ---- Local btrfs snapshots of /home via snapper ----
      services.snapper.configs.${snapName} = {
        ALLOW_USERS = [ cfg.user ];
        FSTYPE = "btrfs";
        SUBVOLUME = cfg.snapshots.subvolume;
        TIMELINE_CLEANUP = true;
        TIMELINE_CREATE = true;
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_HOURLY = "7";
      };

      systemd.services = {
        # The NixOS snapper module only writes the config and timers. It does not
        # create the .snapshots subvolume that snapper needs, so create it once
        # before the timeline service is allowed to run.
        "snapper-${snapName}-init" = {
          description = "Create btrfs .snapshots subvolume for snapper on ${cfg.snapshots.subvolume}";

          before = [
            "snapper-cleanup.service"
            "snapper-timeline.service"
          ];

          after = [ "local-fs.target" ];
          requires = [ "local-fs.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.btrfs-progs}/bin/btrfs subvolume create ${cfg.snapshots.subvolume}/.snapshots";
            RemainAfterExit = true;
          };

          unitConfig.ConditionPathExists = "!${cfg.snapshots.subvolume}/.snapshots";
        };

        snapper-projects = {
          description = "Snapshot btrfs subvolumes under ${cfg.snapshots.projectsDir} alongside snapper";

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe snapshotProjects;
          };
        };

        snapper-timeline.onSuccess = [ "snapper-projects.service" ];
      };
    })

    (lib.mkIf cfg.local.enable {
      # ---- Local Restic backup to a dedicated disk ----
      fileSystems.${cfg.local.mountPoint} = {
        fsType = cfg.local.fsType;
        device = cfg.local.device;

        options = [
          "defaults"
          "noatime"
          "nofail"
        ];
      };

      services.restic.backups.local = {
        inherit (cfg) passwordFile;
        backupPrepareCommand = unlockStale;
        createWrapper = true;

        exclude = commonExcludes ++ [
          ".snapshots"

          "/home/${cfg.user}/Downloads"
          "/home/${cfg.user}/3rd-party"
          "/home/${cfg.user}/.lmstudio/models"

          # Exclude any directory named "data" below ~/Projects, but not arbitrary
          # "data" directories elsewhere in the home directory.
          "/home/${cfg.user}/Projects/data"
          "/home/${cfg.user}/Projects/**/data"

          # Large, reinstallable game content.
          "/home/${cfg.user}/.local/share/Steam/steamapps"
        ];

        extraBackupArgs = commonExtraBackupArgs;
        initialize = true;
        paths = [ cfg.snapshots.subvolume ];

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 2"
        ];

        repository = "${cfg.local.mountPoint}/restic";

        timerConfig = {
          OnCalendar = cfg.local.timer;
          Persistent = true;
        };
      };

      # Never let restic write into a stale mountpoint on the root filesystem:
      # skip the backup entirely when the disk is not mounted.
      systemd.services.restic-backups-local = {
        unitConfig.RequiresMountsFor = cfg.local.mountPoint;
        onFailure = [ notifyOnFailure ];
      };
    })

    (lib.mkIf (cfg.remote.enable || cfg.local.enable) {
      # Instance name is the failed unit, e.g. backup-failure-notify@restic-backups-gdrive.service.
      systemd.services."backup-failure-notify@" = {
        description = "Desktop notification for failed backup %i";

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
        };

        # Delivered only while the user has a session bus; a missed notification
        # repeats with the next scheduled failure.
        script = ''
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
          notify-send --urgency=critical --app-name=Backups --icon=dialog-error \
            "Backup failed: $1" "Check: journalctl -u $1"
        '';

        path = [ pkgs.libnotify ];
        scriptArgs = "%i";
      };
    })
  ];
}
