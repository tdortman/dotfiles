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
  defaultRuntimeReadonlyPaths = [ "/run" ];

  defaultDevicePaths = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
  ];

  normalizeHomePath =
    path:
    let
      stripped = lib.removePrefix "/" path;
    in
    if stripped == "" then null else stripped;

  bindHomePathLines =
    paths: mode:
    concatMapStringsSep "\n" (rel: ''
      bindHomePath ${lib.escapeShellArg rel} ${mode}
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
    defaultRuntimeReadonlyPaths
    defaultDevicePaths
    ;

  mkWrapPackage =
    pkgs:
    {
      package,
      homePaths ? [ ],
      homePathsReadOnly ? [ ],
      binary ? null,
      homeFiles ? [ ],
      extraPkgs ? [ ],
      extraReadwriteDirs ? [ ],
      extraReadonlyDirs ? [ ],
      runtimeReadonlyPaths ? defaultRuntimeReadonlyPaths,
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
      binName = if binary != null then binary else pname;
      mainProgram = "${lib.getBin package}/bin/${binName}";
      sandboxedName = "sandboxed-${binName}";

      homePaths' = lib.filter (p: p != null) (map normalizeHomePath homePaths);
      homePathsReadOnly' = lib.filter (p: p != null) (map normalizeHomePath homePathsReadOnly);
      homeFiles' = lib.filter (p: p != null) (map normalizeHomePath homeFiles);

      sandboxPkgs = lib.unique ([ package ] ++ commonPkgs ++ extraPkgs);
      sandboxPath = lib.makeBinPath sandboxPkgs;

      extraBwrapArgsShell = lib.escapeShellArgs extraBwrapArgs;

      bindHostPathLines =
        paths: mode:
        let
          flag = if mode == "ro" then "ro-bind" else "bind";
        in
        concatMapStringsSep "\n" (path: ''
          hostPath=${lib.escapeShellArg path}
          if [[ -e "$hostPath" ]]; then
            bwrapArgs+=(--${flag} "$hostPath" "$hostPath")
          fi
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



          bindProfileBinPath() {
            local entry="$1"
            local profileRoot=""

            case "$entry" in
              /run/*)
                return
                ;;
              /etc/profiles/per-user/*/bin)
                profileRoot="''${entry%/bin}"
                ;;
              /nix/var/nix/profiles/*/bin)
                profileRoot="''${entry%/bin}"
                ;;
              *)
                return
                ;;
            esac

            if [[ -d "$profileRoot" ]]; then
              bwrapArgs+=(--ro-bind "$profileRoot" "$profileRoot")
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


          bindHomePath() {
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

          ${bindHostPathLines runtimeReadonlyPaths "ro"}

          bwrapArgs+=(
            --tmpfs /tmp
            --tmpfs "$realHome"
            --setenv HOME "$realHome"
            --setenv LANG "''${LANG:-C.UTF-8}"
            --setenv TERM "''${TERM:-xterm-256color}"
            --ro-bind "$jailPasswd" /etc/passwd
            --ro-bind "$jailGroup" /etc/group
          )

          bwrapArgs+=(--ro-bind /nix/store /nix/store)

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

          ${bindHomePathLines homePaths' "rw"}

          ${bindHomePathLines homePathsReadOnly' "ro"}

          ${concatMapStringsSep "\n" (rel: ''
            rel=${lib.escapeShellArg rel}
            src="$realHome/$rel"
            dst="$realHome/$rel"
            if [[ ! -e "$src" ]]; then
              mkdir -p "$(dirname "$src")"
              : > "$src"
            fi
            bwrapArgs+=(--ro-bind "$src" "$dst")
            bindResolvedHomeSymlinksUnder "$src"
          '') homeFiles'}

          ${bindHostPathLines extraReadwriteDirs "bind"}
          ${bindHostPathLines extraReadonlyDirs "ro"}

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
