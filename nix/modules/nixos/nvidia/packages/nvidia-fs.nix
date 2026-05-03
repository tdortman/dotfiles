{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags ? [ ],
  cudaPkgs,
  nvidiaKernelModule,
  nvidiaKernelSourceDir,
  kmod,
  xz,
  binutils,
}:

stdenv.mkDerivation rec {
  pname = "nvidia-fs";
  version = cudaPkgs.nvidia_fs.version;

  src = "${cudaPkgs.nvidia_fs}/src/nvidia-fs-${lib.versions.majorMinor version}";

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    kmod
    xz
    binutils
  ];

  dontConfigure = true;
  dontStrip = true;
  dontPatchELF = true;

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

    substituteInPlace nvfs-dma.c \
      --replace-fail 'static bool nvfs_peek_next_bvec(struct request *req, struct req_iterator *req_iter,' 'static bool nvfs_peek_next_bvec(struct request *req, struct blk_map_iter *req_iter,' \
      --replace-fail 'static void nvfs_advance_bvec(struct req_iterator *req_iter, struct bio_vec *bvec)' 'static void nvfs_advance_bvec(struct blk_map_iter *req_iter, struct bio_vec *bvec)' \
      --replace-fail 'struct req_iterator *req_iter,' 'struct blk_map_iter *req_iter,' \
      --replace-fail 'struct req_iterator *req_iter = &iter->iter;' 'struct blk_map_iter *req_iter = &iter->iter;'

    substituteInPlace nvfs-mmap.c \
      --replace-fail 'vm_flags = ACCESS_PRIVATE(vma, __vm_flags);' 'vm_flags = vma->vm_flags;'
  '';

  preBuild = ''
    export NVIDIA_MODULES
    NVIDIA_MODULES="$(find ${nvidiaKernelModule}/lib/modules/${kernel.modDirVersion} -type f -name 'nvidia.ko*' | sort)"

    if [ -z "$NVIDIA_MODULES" ]; then
      echo "Could not find nvidia.ko in ${nvidiaKernelModule}/lib/modules/${kernel.modDirVersion}" >&2
      exit 1
    fi
  '';

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

  installPhase = ''
    runHook preInstall
    install -D -m 444 nvidia-fs.ko $out/lib/modules/${kernel.modDirVersion}/extra/nvidia-fs.ko
    runHook postInstall
  '';

  meta = {
    description = "NVIDIA GPUDirect Storage nvidia-fs kernel module";
    homepage = "https://docs.nvidia.com/gpudirect-storage/";
    license = cudaPkgs.nvidia_fs.meta.license or lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
