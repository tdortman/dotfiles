{
  config,
  lib,
  pkgs,
  ...
}:
let

  agentSandboxLib = import ./lib.nix { inherit lib; };
  wrapPackage = agentSandboxLib.mkWrapPackage pkgs;

  isValidMountPath = path: path == "~" || lib.hasPrefix "~/" path || lib.hasPrefix "/" path;

  mountPathType = lib.types.addCheck lib.types.str (
    path:
    lib.assertMsg (isValidMountPath path) ''
      agent-sandbox mount path must start with ~/ or / (for example "~/.agents" or "/run/user/1000"), got: ${path}
    ''
  );

  mountPathDescription = ''
    Each entry must be an absolute path: `~/…` under the invoking user's `$HOME`
    (for example `"~/.agents"`), or `/…` on the host (for example `"/run/user/1000"`).
  '';

  mountOptions = {
    readonlyDirs = lib.mkOption {
      type = lib.types.listOf mountPathType;
      default = [ ];
      description = ''
        Directories mounted read-only. ${mountPathDescription}
      '';
    };

    readwriteDirs = lib.mkOption {
      type = lib.types.listOf mountPathType;
      default = [ ];
      description = ''
        Directories mounted read-write. ${mountPathDescription}
      '';
    };

    readonlyFiles = lib.mkOption {
      type = lib.types.listOf mountPathType;
      default = [ ];
      description = ''
        Files mounted read-only (for example `.gitconfig` or a socket under `/run`).
        ${mountPathDescription}
      '';
    };

    readwriteFiles = lib.mkOption {
      type = lib.types.listOf mountPathType;
      default = [ ];
      description = ''
        Files mounted read-write. ${mountPathDescription}
      '';
    };
  };

  packageOptions = mountOptions // {
    package = lib.mkPackageOption pkgs "llm-agents" { };

    binary = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "copilot";
      description = ''
        Optional executable name within {option}`package` (basename only).
        When unset, resolved automatically via `lib.getExe`.
        Set this when the package's default main program is not the agent CLI
        you want to wrap, or when `lib.getExe` does not resolve correctly.
      '';
    };

    extraPkgs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Extra packages available inside the sandbox (on `PATH` and in the Nix store bind set).
      '';
    };

    runtimeReadonlyDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = agentSandboxLib.defaultRuntimeReadonlyDirs;
      description = ''
        Absolute runtime directories mounted read-only. Defaults expose selected
        `/run` entries for the system profile, setuid wrappers, and OpenGL
        drivers.
      '';
    };

    devicePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = agentSandboxLib.defaultDevicePaths;
      description = ''
        Device nodes mounted into the sandbox. Defaults expose NVIDIA devices
        when present so CUDA builds and tests can run.
      '';
    };

    blockEnvVars = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = agentSandboxLib.defaultBlockEnvVars;
      description = ''
        Environment variables stripped from the parent process before starting the sandbox.
        All other variables are inherited (for example devShell exports).
      '';
    };

    forwardPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When enabled, prepend the sandbox toolchain to the parent `PATH` and bind
        `/nix/store` entries from that path read-only. Useful in `nix develop`.
      '';
    };

    exposeWorkingDirectory = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bind the current working directory read-write and start the sandbox there.";
    };

    followHomeSymlinks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Resolve symlinks found under allowed $HOME directories and mount their targets
        read-only, so chezmoi-managed config symlinks work without exposing the
        whole repository that contains their targets.
      '';
    };

    extraBwrapArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional bubblewrap arguments inserted before `--`.";
    };
  };

  mergePackageMounts =
    pkgCfg:
    pkgCfg
    // {
      readonlyDirs = lib.unique (cfg.readonlyDirs ++ pkgCfg.readonlyDirs);
      readwriteDirs = lib.unique (cfg.readwriteDirs ++ pkgCfg.readwriteDirs);
      readonlyFiles = lib.unique (cfg.readonlyFiles ++ pkgCfg.readonlyFiles);
      readwriteFiles = lib.unique (cfg.readwriteFiles ++ pkgCfg.readwriteFiles);
    };

  cfg = config.agent-sandbox;
in
{
  options.agent-sandbox = {
    enable = lib.mkEnableOption "bubblewrap home sandbox helpers for AI agent CLIs";

    packages = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule { options = packageOptions; });
      default = [ ];
      description = ''
        Agent packages to wrap and install system-wide. Each entry produces the
        package binaries plus `bin/sandboxed-<mainProgram>` where `mainProgram` is
        resolved from the package via `lib.getExe`.
      '';
    };
  }
  // mountOptions
  // {
    readonlyDirs = mountOptions.readonlyDirs // {
      description = ''
        Read-only directories shared by every wrapped agent (merged with per-package
        `readonlyDirs`).
      '';
    };

    readwriteDirs = mountOptions.readwriteDirs // {
      description = ''
        Read-write directories shared by every wrapped agent (merged with per-package
        `readwriteDirs`).
      '';
    };

    readonlyFiles = mountOptions.readonlyFiles // {
      description = ''
        Read-only files shared by every wrapped agent (merged with per-package
        `readonlyFiles`).
      '';
    };

    readwriteFiles = mountOptions.readwriteFiles // {
      description = ''
        Read-write files shared by every wrapped agent (merged with per-package
        `readwriteFiles`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = map (value: wrapPackage (mergePackageMounts value)) cfg.packages;

    nixpkgs.overlays = lib.mkAfter [
      (final: prev: {
        agentSandbox = {
          inherit (agentSandboxLib)
            mkWrapPackage
            defaultCommonPkgs
            defaultBlockEnvVars
            defaultRuntimeReadonlyDirs
            defaultDevicePaths
            ;
          wrapPackage = agentSandboxLib.mkWrapPackage final;
        };
      })
    ];
  };
}
