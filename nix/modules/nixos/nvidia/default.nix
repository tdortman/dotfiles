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
        type = lib.types.lazyAttrsOf lib.types.package;
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

      resetBeforeResume = {
        enable = lib.mkEnableOption ''
          a PCI function-level reset of the GPU in the initrd before the hibernation image is restored.
          Firmware lights the display engine of a GPU with a monitor attached during resume, and the
          driver then times out allocating display window channels, which leaves the GPU's display
          stack dead until the next reboot
        '';

        pciAddress = lib.mkOption {
          type = lib.types.strMatching "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]";
          example = "0000:0d:00.0";
          description = "PCI address of the GPU to reset";
        };
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

                # nvidia-modeset frees the device twice when a failed resume
                # revokes it, oopsing inside the PM notifier. Upstream PR
                # NVIDIA/open-gpu-kernel-modules#1395
                (pkgs.fetchpatch {
                  hash = "sha256-aWzj+3AR7xjvWp5IL5iSNIts0SKp9kT35zgXUINBuhc=";
                  name = "nvidia-modeset-ignore-nested-revoke.patch";
                  url = "https://github.com/NVIDIA/open-gpu-kernel-modules/commit/5db24a72350ab2679376132ac8e31a06a0950343.patch";
                })
              ];
            });
          };

          open = true;
          videoAcceleration = true;
        };

        services.xserver.videoDrivers = [ "nvidia" ];
      })

      (lib.mkIf (cfg.driver.enable && cfg.driver.resetBeforeResume.enable) {
        assertions = [
          {
            assertion = config.boot.initrd.systemd.enable;
            message = "nvidia.driver.resetBeforeResume needs boot.initrd.systemd.enable, which runs the reset before systemd-hibernate-resume.";
          }
        ];

        boot.initrd.systemd.services.nvidia-gpu-reset = {
          description = "Reset the NVIDIA GPU before restoring the hibernation image";
          before = [ "systemd-hibernate-resume.service" ];
          wantedBy = [ "systemd-hibernate-resume.service" ];
          serviceConfig.Type = "oneshot";
          unitConfig.DefaultDependencies = false;

          script = ''
            echo 1 > /sys/bus/pci/devices/${cfg.driver.resetBeforeResume.pciAddress}/reset
          '';
        };
      })
    ];
}
