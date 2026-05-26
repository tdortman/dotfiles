{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let

  agentSandboxLib = inputs.self.lib;
  wrapPackage = agentSandboxLib.mkWrapPackage pkgs;

  packageOptions = {
    package = lib.mkPackageOption pkgs "llm-agents" { };

    binary = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Binary name when it differs from the package name.";
    };

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

    extraPkgs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Extra packages available inside the sandbox (on `PATH` and in the Nix store bind set).
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
    runtimeReadonlyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = agentSandboxLib.defaultRuntimeReadonlyPaths;
      description = ''
        Absolute runtime paths mounted read-only. Defaults expose `/run` for
        compatibility with NixOS profiles, GPU drivers, and devShell tools.
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

  cfg = config.agent-sandbox;
in
{
  options.agent-sandbox = {
    enable = lib.mkEnableOption "bubblewrap home sandbox helpers for AI agent CLIs";

    packages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { options = packageOptions; });
      default = { };
      description = ''
        Agent packages to wrap and install system-wide. Each entry produces
        `bin/<name>` and `bin/sandboxed-<name>`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mapAttrsToList (_: value: wrapPackage value) cfg.packages;

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
