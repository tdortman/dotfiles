{
  lib,
  ...
}:
let
  inherit (lib) concatMapStringsSep;

  defaultCommonPkgs =
    pkgs: with pkgs; [
      bashInteractive
      curl
      wget
      jq
      git
      which
      ripgrep
      gnugrep
      gawkInteractive
      ps
      findutils
      gzip
      unzip
      gnutar
      diffutils
      gnused
    ];

  defaultBlockEnvVars = [ ];

  defaultRuntimeReadonlyDirs = [
    "/run/current-system"
    "/run/wrappers"
    "/run/opengl-driver"
    "/run/opengl-driver-32"
  ];

  defaultDevicePaths = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
  ];

  isHomeMountPath = path: path == "~" || lib.hasPrefix "~/" path;

  isHostMountPath = path: lib.hasPrefix "/" path;

  homeMountRel =
    path:
    if path == "~" then "" else lib.removePrefix "~/" path;

  splitMountPaths =
    paths:
    let
      invalid = lib.filter (p: !isHomeMountPath p && !isHostMountPath p) paths;
    in
    if invalid != [ ] then
      builtins.throw ''
        agent-sandbox: mount paths must start with ~/ or / (for example "~/.agents" or "/run/user/1000").
        Invalid: ${lib.concatStringsSep ", " (map (p: ''"${p}"'') invalid)}
      ''
    else
      {
        home = map homeMountRel (lib.filter isHomeMountPath paths);
        abs = lib.filter isHostMountPath paths;
      };

  bindHomeDirLines =
    paths: mode:
    concatMapStringsSep "\n" (rel: ''
      bindHomeDir ${lib.escapeShellArg rel} ${mode}
    '') paths;

  bindHomeFileLines =
    paths: mode:
    concatMapStringsSep "\n" (rel: ''
      bindHomeFile ${lib.escapeShellArg rel} ${mode}
    '') paths;

  blockEnvVarLines =
    vars:
    concatMapStringsSep "\n" (var: ''
      unset ${var} || true
    '') vars;
in
rec {
  inherit
    defaultCommonPkgs
    defaultBlockEnvVars
    defaultRuntimeReadonlyDirs
    defaultDevicePaths
    ;

  mkWrapPackage =
    pkgs:
    {
      package,
      binary ? null,
      readonlyDirs ? [ ],
      readwriteDirs ? [ ],
      readonlyFiles ? [ ],
      readwriteFiles ? [ ],
      extraPkgs ? [ ],
      runtimeReadonlyDirs ? defaultRuntimeReadonlyDirs,
      devicePaths ? defaultDevicePaths,
      commonPkgs ? defaultCommonPkgs pkgs,
      blockEnvVars ? defaultBlockEnvVars,
      forwardPath ? true,
      exposeWorkingDirectory ? true,
      followHomeSymlinks ? true,
      extraBwrapArgs ? [ ],
    }:
    let
      pname = lib.getName package;
      binName =
        if binary != null then
          binary
        else
          builtins.baseNameOf (lib.getExe package);
      mainProgram =
        if binary != null then
          lib.getExe' package binary
        else
          lib.getExe package;
      sandboxedName = "sandboxed-${binName}";

      readonlyDirs' = splitMountPaths readonlyDirs;
      readwriteDirs' = splitMountPaths readwriteDirs;
      readonlyFiles' = splitMountPaths readonlyFiles;
      readwriteFiles' = splitMountPaths readwriteFiles;

      sandboxPkgs = lib.unique ([ package ] ++ commonPkgs ++ extraPkgs);
      sandboxPath = lib.makeBinPath sandboxPkgs;

      extraBwrapArgsShell = lib.escapeShellArgs extraBwrapArgs;

      bindHostPathLines =
        paths: mode:
        let
          mountMode = if mode == "ro" then "ro" else "rw";
        in
        concatMapStringsSep "\n" (hostPath: ''
          bindSandboxHostPath ${lib.escapeShellArg hostPath} ${mountMode}
        '') paths;

      bindDevicePathLines =
        paths:
        concatMapStringsSep "\n" (path: ''
          devPath=${lib.escapeShellArg path}
          if [[ -e "$devPath" ]]; then
            bwrapArgs+=(--dev-bind "$devPath" "$devPath")
          fi
        '') paths;

      exposeWorkingDirectoryBlock = lib.optionalString exposeWorkingDirectory ''
        cwd=$(readlink -f "$PWD")
        if [[ -e "$cwd" && "$cwd" != "$realHome" ]]; then
          bwrapArgs+=(--bind "$cwd" "$cwd" --chdir "$cwd")
        else
          bwrapArgs+=(--chdir "$realHome")
        fi
      '';
    in
    let
      launcher = pkgs.writeShellApplication {
        name = sandboxedName;
        runtimeInputs = [
          pkgs.bubblewrap
          pkgs.coreutils
          pkgs.nix
          pkgs.findutils
        ];
        text = ''
          set -euo pipefail

          if [[ -z "''${HOME:-}" ]]; then
            echo "agent-sandbox: HOME is not set" >&2
            exit 1
          fi

          realHome=$(readlink -f "$HOME")
          sandboxPath=${lib.escapeShellArg sandboxPath}

          ${blockEnvVarLines blockEnvVars}
          followHomeSymlinks=${if followHomeSymlinks then "1" else "0"}

          declare -A sandboxDirsCreated=()
          declare -A sandboxPathsBound=()

          isSandboxPathCovered() {
            local path="$1"
            local key=""

            for key in "''${!sandboxPathsBound[@]}"; do
              if [[ "$path" == "$key" || "$path" == "$key"/* ]]; then
                return 0
              fi
            done

            return 1
          }

          ensureSandboxDir() {
            local dir="$1"

            if [[ -z "$dir" || "$dir" == "/" ]]; then
              return
            fi

            ensureSandboxDir "$(dirname "$dir")"

            if [[ -n "''${sandboxDirsCreated[$dir]+x}" ]]; then
              return
            fi

            sandboxDirsCreated[$dir]=1
            bwrapArgs+=(--dir "$dir")
          }

          bindSandboxHostPath() {
            local dest="$1"
            local mountMode="$2"
            local target=""

            if isSandboxPathCovered "$dest"; then
              return
            fi

            if [[ ! -e "$dest" && ! -L "$dest" ]]; then
              return
            fi

            if [[ -L "$dest" ]]; then
              target=$(readlink -f "$dest" || true)
              if [[ -z "$target" || ! -e "$target" ]]; then
                return
              fi

              ensureSandboxDir "$(dirname "$dest")"

              if [[ "$target" == /nix/store/* ]]; then
                bwrapArgs+=(--symlink "$target" "$dest")
              elif [[ "$mountMode" == "rw" ]]; then
                bwrapArgs+=(--bind "$target" "$dest")
              else
                bwrapArgs+=(--ro-bind "$target" "$dest")
              fi
              sandboxPathsBound[$dest]=1
              return
            fi

            ensureSandboxDir "$(dirname "$dest")"
            if [[ "$mountMode" == "rw" ]]; then
              bwrapArgs+=(--bind "$dest" "$dest")
            else
              bwrapArgs+=(--ro-bind "$dest" "$dest")
            fi
            sandboxPathsBound[$dest]=1
          }

          bindProfileBinPath() {
            local entry="$1"
            local profileRoot=""

            case "$entry" in
              /etc/profiles/per-user/*/bin|/nix/var/nix/profiles/*/bin)
                profileRoot="''${entry%/bin}"
                ;;
              /run/*)
                case "$entry" in
                  */bin)
                    profileRoot="''${entry%/bin}"
                    ;;
                  *)
                    return
                    ;;
                esac
                ;;
              *)
                return
                ;;
            esac

            if [[ -d "$profileRoot" || -L "$profileRoot" ]]; then
              bindSandboxHostPath "$profileRoot" ro
            fi
          }

          bindPathEntries() {
            local pathVar="$1"
            local entry
            if [[ -z "''${!pathVar:-}" ]]; then
              return
            fi
            IFS=':' read -ra entries <<< "''${!pathVar}"
            for entry in "''${entries[@]}"; do
              bindProfileBinPath "$entry"
            done
          }

          bindEtcFile() {
            local path="$1"
            if [[ -e "$path" ]]; then
              bwrapArgs+=(--ro-bind "$path" "$path")
            fi
          }
          ensureSandboxTmpDir() {
            local dir="$1"
            local rel=""
            local current="/tmp"
            local part=""

            case "$dir" in
              /tmp)
                return
                ;;
              /tmp/*)
                ;;
              *)
                return
                ;;
            esac

            rel="''${dir#/tmp/}"
            IFS='/' read -ra parts <<< "$rel"
            for part in "''${parts[@]}"; do
              [[ -n "$part" ]] || continue
              current="$current/$part"
              bwrapArgs+=(--dir "$current")
            done
          }

          ensureSandboxHomeDir() {
            local dir="$1"
            local rel=""
            local current=""
            local part=""

            if [[ "$dir" != "$realHome" && "$dir" != "$realHome"/* ]]; then
              return
            fi

            rel="''${dir#"$realHome"}"
            rel="''${rel#/}"
            current="$realHome"

            if [[ -z "$rel" ]]; then
              return
            fi

            IFS='/' read -ra parts <<< "$rel"
            for part in "''${parts[@]}"; do
              [[ -n "$part" ]] || continue
              current="$current/$part"
              bwrapArgs+=(--dir "$current")
            done
          }

          bindResolvedHomeSymlinkTarget() {
            local link="$1"
            local target=""

            if [[ "$followHomeSymlinks" != "1" || ! -L "$link" ]]; then
              return
            fi

            target=$(readlink -f "$link" || true)
            if [[ -z "$target" || ! -e "$target" ]]; then
              return
            fi

            case "$target" in
              "$realHome"/*)
                ensureSandboxHomeDir "$(dirname "$target")"
                bwrapArgs+=(--ro-bind "$target" "$target")
                ;;
              /nix/store/*)
                ;;
            esac
          }

          bindResolvedHomeSymlinksUnder() {
            local root="$1"
            local link=""

            if [[ "$followHomeSymlinks" != "1" ]]; then
              return
            fi

            if [[ -L "$root" ]]; then
              bindResolvedHomeSymlinkTarget "$root"
              return
            fi

            if [[ ! -d "$root" ]]; then
              return
            fi

            while IFS= read -r -d "" link; do
              bindResolvedHomeSymlinkTarget "$link"
            done < <(find "$root" -type l -print0)
          }

          bindHomeDir() {
            local rel="$1"
            local mode="$2"
            local src="$realHome/$rel"
            local dst="$realHome/$rel"

            if [[ ! -e "$src" ]]; then
              mkdir -p "$src"
            fi

            if [[ "$mode" == "ro" ]]; then
              bwrapArgs+=(--ro-bind "$src" "$dst")
            else
              bwrapArgs+=(--bind "$src" "$dst")
            fi
            bindResolvedHomeSymlinksUnder "$src"
          }

          bindHomeFile() {
            local rel="$1"
            local mode="$2"
            local src="$realHome/$rel"
            local dst="$realHome/$rel"

            if [[ ! -e "$src" ]]; then
              mkdir -p "$(dirname "$src")"
              : > "$src"
            fi

            if [[ "$mode" == "ro" ]]; then
              bwrapArgs+=(--ro-bind "$src" "$dst")
            else
              bwrapArgs+=(--bind "$src" "$dst")
            fi
            bindResolvedHomeSymlinksUnder "$src"
          }

          jailPasswd="$realHome/.local/share/agent-sandbox/passwd"
          jailGroup="$realHome/.local/share/agent-sandbox/group"
          if [[ ! -e "$jailPasswd" || ! -e "$jailGroup" ]]; then
            mkdir -p "$realHome/.local/share/agent-sandbox"
            nologin=${pkgs.shadow}/bin/nologin
            {
              echo "root:x:0:0:System administrator:/root:$nologin"
              echo "$(id -un):x:$(id -u):$(id -g)::$realHome:$nologin"
            } > "$jailPasswd"
            {
              echo "root:x:0:"
              echo "$(id -gn):x:$(id -g):"
            } > "$jailGroup"
          fi

          bwrapArgs=(
            --die-with-parent
            --new-session
            --unshare-user
            --unshare-ipc
            --unshare-pid
            --unshare-uts
            --share-net
            --proc /proc
            --dev /dev
          )

          bwrapArgs+=(--ro-bind /nix/store /nix/store)

          ${bindHostPathLines runtimeReadonlyDirs "ro"}

          bwrapArgs+=(
            --tmpfs /tmp
            --tmpfs "$realHome"
            --setenv HOME "$realHome"
            --setenv LANG "''${LANG:-C.UTF-8}"
            --setenv TERM "''${TERM:-xterm-256color}"
            --ro-bind "$jailPasswd" /etc/passwd
            --ro-bind "$jailGroup" /etc/group
          )

          if [[ -L /bin/sh ]]; then
            shPath=$(readlink -f /bin/sh)
            bwrapArgs+=(--ro-bind "$shPath" "$shPath")
            bwrapArgs+=(--symlink "$(readlink /bin/sh)" /bin/sh)
          elif [[ -e /bin/sh ]]; then
            bwrapArgs+=(--ro-bind /bin/sh /bin/sh)
          fi

          bindEtcFile /etc/hosts
          bindEtcFile /etc/nsswitch.conf
          bindEtcFile /etc/resolv.conf
          if [[ -d /etc/ssl ]]; then
            bwrapArgs+=(--ro-bind /etc/ssl /etc/ssl)
          fi
          # NixOS symlinks /etc/ssl/certs/* into /etc/static/ssl; bind targets too.
          if [[ -d /etc/static/ssl ]]; then
            bwrapArgs+=(--ro-bind /etc/static/ssl /etc/static/ssl)
          fi
          if [[ -L /etc/localtime ]]; then
            tz=$(readlink -f /etc/localtime)
            bwrapArgs+=(--ro-bind "$tz" "$tz")
            bwrapArgs+=(--symlink "$(readlink /etc/localtime)" /etc/localtime)
          fi
          ${bindDevicePathLines devicePaths}
          if [[ -n "''${TMPDIR:-}" ]]; then
            ensureSandboxTmpDir "$TMPDIR"
          fi
          if [[ -n "''${TMP:-}" ]]; then
            ensureSandboxTmpDir "$TMP"
          fi
          if [[ -n "''${TEMP:-}" ]]; then
            ensureSandboxTmpDir "$TEMP"
          fi

          ${bindHomeDirLines readonlyDirs'.home "ro"}
          ${bindHomeDirLines readwriteDirs'.home "rw"}
          ${bindHostPathLines readonlyDirs'.abs "ro"}
          ${bindHostPathLines readwriteDirs'.abs "bind"}

          ${bindHomeFileLines readonlyFiles'.home "ro"}
          ${bindHomeFileLines readwriteFiles'.home "rw"}
          ${bindHostPathLines readonlyFiles'.abs "ro"}
          ${bindHostPathLines readwriteFiles'.abs "bind"}

          ${exposeWorkingDirectoryBlock}

          mergedPath="$sandboxPath"
          ${lib.optionalString forwardPath ''
            if [[ -n "''${PATH:-}" ]]; then
              mergedPath="$sandboxPath:$PATH"
              IFS=':' read -ra parentPathEntries <<< "$PATH"
              for entry in "''${parentPathEntries[@]}"; do
                bindProfileBinPath "$entry"
              done
            fi
          ''}
          bwrapArgs+=(--setenv PATH "$mergedPath")

          bindPathEntries PKG_CONFIG_PATH
          bindPathEntries CMAKE_PREFIX_PATH
          bindPathEntries CPATH
          bindPathEntries LIBRARY_PATH
          bindPathEntries SSL_CERT_FILE
          bindPathEntries NIX_SSL_CERT_FILE

          ${lib.optionalString (extraBwrapArgs != [ ]) ''
            # shellcheck disable=SC2206
            extraArgs=(${extraBwrapArgsShell})
            bwrapArgs+=("''${extraArgs[@]}")
          ''}

          exec ${pkgs.bubblewrap}/bin/bwrap "''${bwrapArgs[@]}" -- ${lib.escapeShellArg mainProgram} "$@"
        '';
      };
    in
    pkgs.symlinkJoin {
      name = "${pname}-agent-sandbox";
      paths = [ package ];
      postBuild = ''
        ln -s ${launcher}/bin/${sandboxedName} ''$out/bin/${sandboxedName}
      '';
    };
}
