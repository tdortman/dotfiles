{
  lib,
  stdenv,
  binutils,
  cudaPkgs,
  kernel,
  kmod,
  nvidiaKernelModule,
  nvidiaKernelSourceDir,
  xz,
  kernelModuleMakeFlags ? [ ],
  ...
}:

stdenv.mkDerivation rec {
  pname = "nvidia-fs";
  version = cudaPkgs.nvidia_fs.version;
  src = "${cudaPkgs.nvidia_fs}/src/nvidia-fs-${lib.versions.majorMinor version}";

  postPatch = ''
    patchShebangs configure create_nv.symvers.sh

    substituteInPlace configure \
      --replace-fail 'export MODULES_DIR=/lib/modules/$KVER' 'export MODULES_DIR=${kernel.dev}/lib/modules/$KVER'

    substituteInPlace Makefile \
      --replace-fail '/sbin/modinfo' 'modinfo' \
      --replace-fail '/bin/ls' 'ls' \
      --replace-fail 'ccflags-y += -I/usr/lib/gcc/x86_64-linux-gnu/7/include/' "" \
      --replace-fail '@ ./create_nv.symvers.sh' '@ ./create_nv.symvers.sh $(KVER)'

    substituteInPlace create_nv.symvers.sh \
      --replace-fail '/sbin/modinfo' 'modinfo' \
      --replace-fail '/bin/ls' 'ls' \
      --replace-fail '/bin/cp' 'cp' \
      --replace-fail '/bin/rm' 'rm' \
      --replace-fail 'for mod in nvidia $(ls /lib/modules/$KVER/updates/dkms/nvidia*.ko* 2>/dev/null)' 'for mod in $NVIDIA_MODULES nvidia $(ls /lib/modules/$KVER/updates/dkms/nvidia*.ko* 2>/dev/null)'


    substituteInPlace nvfs-mmap.c \
      --replace-fail 'vm_flags = ACCESS_PRIVATE(vma, __vm_flags);' 'vm_flags = vma->vm_flags;'
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    binutils
    kmod
    xz
  ];

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "KVER=${kernel.modDirVersion}"
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "NVIDIA_SRC_DIR=${nvidiaKernelSourceDir}"
    ]
    ++ lib.optionals stdenv.cc.isClang [
      "C_INCLUDE_PATH=${lib.getLib stdenv.cc.cc}/lib/clang/${lib.versions.major stdenv.cc.cc.version}/include"
    ];

  preBuild = ''
    export NVIDIA_MODULES
    NVIDIA_MODULES="$(find ${nvidiaKernelModule}/lib/modules/${kernel.modDirVersion} -type f -name 'nvidia.ko*' | sort)"

    if [ -z "$NVIDIA_MODULES" ]; then
      echo "Could not find nvidia.ko in ${nvidiaKernelModule}/lib/modules/${kernel.modDirVersion}" >&2
      exit 1
    fi
  '';

  installPhase = ''
    runHook preInstall
    install -D -m 444 nvidia-fs.ko $out/lib/modules/${kernel.modDirVersion}/extra/nvidia-fs.ko
    runHook postInstall
  '';

  dontConfigure = true;
  dontPatchELF = true;
  dontStrip = true;

  meta = {
    description = "NVIDIA GPUDirect Storage nvidia-fs kernel module";
    homepage = "https://docs.nvidia.com/gpudirect-storage/";
    license = cudaPkgs.nvidia_fs.meta.license or lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
