{
  lib,
  fetchFromGitHub,
  autoAddDriverRunpath,
  config,
  gnused,
  libffi,
  libxml2,
  llvmPackages_22,
  makeWrapper,
  runCommand,
  runtimeShell,
  rustPlatform,
  symlinkJoin,
  writeShellScript,
  z3,
  zlib,
  cudaPackages ? { },
  cudaSupport ? config.cudaSupport,
}:

# runtime/cuda_dispatch.cpp calls cublasGemmEx with CUBLAS_COMPUTE_32F, which CUDA 11.0 introduced.
assert lib.assertMsg (
  cudaSupport -> lib.versionAtLeast (cudaPackages.cudaMajorMinorVersion or "0") "11.0"
) "vx: CUDA support needs a cudaPackages set for CUDA 11.0 or newer";

let
  # vxc links every program against the dispatch backend with a bare `-lffi`.
  clang = writeShellScript "vx-clang" ''
    exec ${llvmPkgs.clang}/bin/clang -L${lib.getLib libffi}/lib "$@"
  '';
  # build.rs probes $CUDA_HOME for include/cuda_runtime.h, lib/libcudart.so, libcublas, and the
  # driver stub in lib/stubs. The runtime headers also pull in crt/ (nvcc before CUDA 13, cuda_crt
  # after) and nv/target (cccl).
  cudaHome = symlinkJoin {
    name = "vx-cuda-home-${cudaPackages.cudaMajorMinorVersion}";

    paths =
      with cudaPackages;
      [
        (lib.getOutput "include" cccl)
        (lib.getOutput "include" cuda_cudart)
        (lib.getLib cuda_cudart)
        (lib.getOutput "stubs" cuda_cudart)
        (lib.getOutput "include" cuda_nvcc)
        (lib.getOutput "include" libcublas)
        (lib.getLib libcublas)
      ]
      ++ lib.optional (lib.versionAtLeast cudaPackages.cudaMajorMinorVersion "13") (
        lib.getOutput "include" cudaPackages.cuda_crt
      );
  };
  dispatchLib = if cudaSupport then "libvx_cuda_dispatch.so" else "libvx_x86_dispatch.so";
  llvm = llvmPkgs.llvm;
  # mlir-sys, tblgen-rs, build.rs and vxc itself all locate LLVM through `llvm-config`, and expect
  # MLIR's libraries, headers and mlir-tblgen under the directories it reports. nixpkgs splits those
  # across several store paths, so merge them and remap llvm-config's answers onto the merged tree.
  llvm-mlir = runCommand "llvm-mlir-${llvm.version}" { } ''
    mkdir -p $out/bin $out/lib $out/include
    ln -s ${llvm.lib}/lib/* ${mlir}/lib/* $out/lib/
    ln -s ${llvm.dev}/include/* ${mlir.dev}/include/* $out/include/
    ln -s ${llvm}/bin/* ${mlir}/bin/* ${llvmPkgs.tblgen}/bin/mlir-tblgen $out/bin/
    cat > $out/bin/llvm-config <<EOF
    #!${runtimeShell}
    res=\$(${llvm.dev}/bin/llvm-config "\$@") || exit \$?
    printf '%s\n' "\$res" | ${gnused}/bin/sed -e 's|${llvm.lib}/lib|$out/lib|g' \
      -e 's|${llvm.dev}/include|$out/include|g' -e 's|${llvm}/bin|$out/bin|g'
    EOF
    chmod +x $out/bin/llvm-config
  '';
  llvmPkgs = llvmPackages_22;
  mlir = llvmPkgs.mlir;
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "vx";
  version = "0.0.3";

  src = fetchFromGitHub {
    owner = "vx-lang";
    repo = "Vx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-D/xbEfBnQeYgncOXkfdr6ZS1L1ygN1sJhRVL8QsC48Y=";
  };

  nativeBuildInputs = [
    llvm-mlir
    makeWrapper
    rustPlatform.bindgenHook
  ]
  ++ lib.optionals cudaSupport [
    autoAddDriverRunpath
    cudaPackages.removeStubsFromRunpathHook
  ];

  buildInputs = [
    libffi
    libxml2
    zlib
  ];

  cargoHash = "sha256-3r6XTi+bRYYeH1IfEUEMrtGZYGulT3eC5Lqqtv3ptiI=";
  env = lib.optionalAttrs cudaSupport { CUDA_HOME = cudaHome; };
  # The upstream suite JITs programs through clang and needs the source checkout layout.
  doCheck = false;

  postInstall = ''
    mkdir -p $out/libexec $out/share/vx
    mv $out/bin/{vxc,vx-format,vx-opt} $out/libexec/
    rm $out/bin/*
    cp target/*/release/libvx_std_core.so $out/lib/
    cp target/*/release/build/vxc-*/out/{${dispatchLib},libvx_mlir_shims.so} $out/lib/

    # Same layout as the upstream release tarball: vxc finds ../lib and ../stdlib on its own.
    cp -r stdlib $out/stdlib
    rm -r $out/stdlib/rust_core
    find $out/stdlib -name '*.vxlib' -delete
    cp -r fleet examples $out/share/vx/

    for tool in vxc vx-format vx-opt; do
      makeWrapper $out/libexec/$tool $out/bin/$tool \
        --prefix PATH : ${lib.makeBinPath [ z3 ]} \
        --set-default LLVM_CONFIG_PATH ${llvm-mlir}/bin/llvm-config \
        --set-default MLIR_TRANSLATE_PATH ${mlir}/bin/mlir-translate \
        --set-default OPT_PATH ${llvm}/bin/opt \
        --set-default LLC_PATH ${llvm}/bin/llc \
        --set-default CLANG_PATH ${clang} \
        --set-default VX_DISPATCH_LIB $out/lib/${dispatchLib} \
        ${lib.optionalString cudaSupport "--set-default VX_LIBDEVICE ${cudaPackages.cuda_nvcc}/nvvm/libdevice/libdevice.10.bc"}
    done
  '';

  # tblgen-rs compiles its C++ shim with -Werror at the build-dependency -O0, where glibc warns
  # about the _FORTIFY_SOURCE nixpkgs injects.
  hardeningDisable = [ "fortify" ];

  meta = {
    description = "Heterogeneous-systems language with memory placement in the type system";
    homepage = "https://vxlang.org";
    license = lib.licenses.asl20-llvm;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "vxc";
  };
})
