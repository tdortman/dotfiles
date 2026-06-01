{
  config,
  lib,
  pkgs,
  ...
}:
let

  agentSandboxLib = import ./lib.nix { inherit lib; };
  wrapPackage = agentSandboxLib.mkWrapPackage pkgs;

  pathOptions = {
    homePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths under $HOME that the sandboxed binary may read and write.
        Example: [ ".omp" ".agents" ].
      '';
    };

    homePathsReadOnly = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths under $HOME that are mounted read-only.";
    };

    homeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Individual files under $HOME mounted read-only (for example `.gitconfig`).
      '';
    };

    extraReadwriteDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Absolute host paths outside $HOME to mount read-write (for example a projects directory).
      '';
    };

    extraReadonlyDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Absolute host paths outside $HOME to mount read-only.";
    };
  };

  packageOptions = pathOptions // {
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

    runtimeReadonlyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = agentSandboxLib.defaultRuntimeReadonlyPaths;
      description = ''
        Absolute runtime paths mounted read-only. Defaults expose selected
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
        Resolve symlinks found under allowed $HOME paths and mount their targets
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

  mergePackagePaths =
    pkgCfg:
    pkgCfg
    // {
      homePaths = lib.unique (cfg.homePaths ++ pkgCfg.homePaths);
      homePathsReadOnly = lib.unique (cfg.homePathsReadOnly ++ pkgCfg.homePathsReadOnly);
      homeFiles = lib.unique (cfg.homeFiles ++ pkgCfg.homeFiles);
      extraReadwriteDirs = lib.unique (cfg.extraReadwriteDirs ++ pkgCfg.extraReadwriteDirs);
      extraReadonlyDirs = lib.unique (cfg.extraReadonlyDirs ++ pkgCfg.extraReadonlyDirs);
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
  // pathOptions
  // {
    homePaths = pathOptions.homePaths // {
      description = ''
        Paths under $HOME shared by every wrapped agent (merged with per-package
        `homePaths`).
      '';
    };

    homePathsReadOnly = pathOptions.homePathsReadOnly // {
      description = ''
        Read-only $HOME paths shared by every wrapped agent (merged with per-package
        `homePathsReadOnly`).
      '';
    };

    homeFiles = pathOptions.homeFiles // {
      description = ''
        Read-only $HOME files shared by every wrapped agent (merged with per-package
        `homeFiles`).
      '';
    };

    extraReadwriteDirs = pathOptions.extraReadwriteDirs // {
      description = ''
        Absolute host paths mounted read-write for every wrapped agent (merged with
        per-package `extraReadwriteDirs`).
      '';
    };

    extraReadonlyDirs = pathOptions.extraReadonlyDirs // {
      description = ''
        Absolute host paths mounted read-only for every wrapped agent (merged with
        per-package `extraReadonlyDirs`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = map (
      value: wrapPackage (mergePackagePaths value)
    ) cfg.packages;

    nixpkgs.overlays = lib.mkAfter [
      (final: prev: {
        agentSandbox = {
          inherit (agentSandboxLib)
            mkWrapPackage
            defaultCommonPkgs
            defaultBlockEnvVars
            defaultRuntimeReadonlyPaths
            defaultDevicePaths
            ;
          wrapPackage = agentSandboxLib.mkWrapPackage final;
        };
      })
    ];
  };
}
