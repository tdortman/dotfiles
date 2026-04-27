{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        system = system;
        config.allowUnfree = true;
      };

      cudaPkgs = pkgs.cudaPackages_13_2;
      llvm = pkgs.llvmPackages_22;

      cudaPackages = with cudaPkgs; [
        cuda_nvcc
        cuda_cudart
        cuda_cccl
        cuda_cuobjdump
      ];

      cuda = {
        arch = "1200";
        sm_target = "sm_120";
        path = pkgs.symlinkJoin {
          name = "cuda-dev-path";
          paths = cudaPackages;
        };
        version = {
          complete = cudaPkgs.cudaMajorMinorVersion;
          major = cudaPkgs.cudaMajorVersion;
          minor = nixpkgs.lib.lists.last (builtins.splitVersion cuda.version.complete);
        };

      };
      buildInputs = cudaPackages ++ [
        pkgs.stdenv.cc.cc.lib
      ];

      nativeBuildInputs = with pkgs; [
        llvm.clang-tools
        llvm.lldb
        meson
        uv
        pkg-config

        cudaPkgs.nsight_systems
        cudaPkgs.nsight_compute
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {

        inherit buildInputs nativeBuildInputs;

        LD_LIBRARY_PATH = "${
          pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)
        }:/run/opengl-driver/lib";

        shellHook = ''
              if [ ! -e .clangd ]; then
                cat > .clangd <<EOF
          CompileFlags:
            Compiler: ${cuda.path}/bin/nvcc
            Add:
              - -xcuda
              - --cuda-path=${cuda.path}
              - -D__INTELLISENSE__
              - -D__CLANGD__
              - -I${cuda.path}/include
              - -I$(pwd)/include
              - -D__LIBCUDAXX__STD_VER=${cuda.version.major}
              - -D__CUDACC_VER_MAJOR__=${cuda.version.major}
              - -D__CUDACC_VER_MINOR__=${cuda.version.minor}
              - -D__CUDA_ARCH__=${cuda.arch}
              - --cuda-gpu-arch=${cuda.sm_target}
              - -D__CUDACC_EXTENDED_LAMBDA__
            Remove:
              - -Xcompiler=*
              - -G
              - "-arch=*"
              - "-Xfatbin*"
              - "-gencode*"
              - "--generate-code*"
              - "--generate-line-info"
              - "--compiler-options*"
              - "--expt-extended-lambda"
              - "--expt-relaxed-constexpr"
              - "-forward-unknown-to-host-compiler"
              - "-Werror=cross-execution-space-call"

          Diagnostics:
            UnusedIncludes: None
            Suppress:
              - variadic_device_fn
              - attributes_not_allowed
              - undeclared_var_use_suggest
              - typename_invalid_functionspec
              - expected_expression
          EOF
                echo ".clangd created by flake shellHook"
              fi
        '';
      };
    };
}
