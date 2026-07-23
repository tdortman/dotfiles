{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nvidia;
in
{
  options.nvidia = {
    cuda = {
      enable = lib.mkEnableOption "CUDA support";
      nvidia-fs.enable = lib.mkEnableOption "nvidia-fs kernel module for GPUDirect Storage";

      packages = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = pkgs.cudaPackages;
        description = "The CUDA packages to use. Defaults to the latest CUDA packages provided by Nixpkgs";
      };
    };

    driver = {
      enable = lib.mkEnableOption "NVIDIA graphics driver";

      package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.nvidiaPackages.stable;
        description = "The NVIDIA driver package to use";
      };
    };
  };

  config =
    let
      pocl-cuda = pkgs.callPackage ../../../packages/pocl-cuda/package.nix {
        cudaPkgs = cfg.cuda.packages;
      };
    in
    lib.mkMerge [
      (lib.mkIf (cfg.cuda.enable || cfg.driver.enable) {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
        };
      })

      (lib.mkIf (cfg.cuda.enable && cfg.driver.enable) {
        # https://developer.nvidia.com/nvidia-development-tools-solutions-err_nvgpuctrperm-permission-issue-performance-counters
        boot.kernelParams = [
          "nvidia.NVreg_RestrictProfilingToAdminUsers=0"
        ];
      })

      (lib.mkIf (cfg.cuda.enable && !cfg.driver.enable) {
        environment.variables.OCL_ICD_FILENAMES = "${pocl-cuda}/etc/OpenCL/vendors/pocl.icd";

        hardware.graphics.extraPackages = [
          pocl-cuda
        ];
      })

      # Base CUDA configuration
      (lib.mkIf cfg.cuda.enable {
        environment.systemPackages = [
          pkgs.cuda.nvtopPackages.nvidia
          cfg.cuda.packages.nsight_systems
          cfg.cuda.packages.nsight_compute
        ];
      })

      # nvidia-fs  Kernel Module Integration
      (lib.mkIf (cfg.cuda.enable && cfg.cuda.nvidia-fs.enable && cfg.driver.enable) {
        boot = {
          extraModulePackages =
            let
              kernelPackages = config.boot.kernelPackages;
            in
            [
              (kernelPackages.callPackage ../../../packages/nvidia-fs/package.nix {
                cudaPkgs = cfg.cuda.packages;
                nvidiaKernelModule = config.hardware.nvidia.package.open;
                nvidiaKernelSourceDir = "${config.hardware.nvidia.package.open.src}/kernel-open/nvidia";
              })
            ];

          kernelModules = [ "nvidia-fs" ];
        };
      })

      # Driver configuration
      (lib.mkIf cfg.driver.enable {
        hardware.nvidia = {
          package = cfg.driver.package // {
            open = cfg.driver.package.open.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [
                # (pkgs.fetchpatch {
                #   name = "kernel-6.19";
                #   url = "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/nvidia/nvidia-utils/kernel-6.19.patch";
                #   hash = "sha256-YuJjSUXE6jYSuZySYGnWSNG5sfVei7vvxDcHx3K+IN4=";
                # })
              ];
            });
          };

          open = true;
          videoAcceleration = true;
        };

        services.xserver.videoDrivers = [ "nvidia" ];
      })
    ];
}
