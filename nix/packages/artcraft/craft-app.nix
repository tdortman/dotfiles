{
  lib,
  stdenv,
  alsa-lib,
  autoPatchelfHook,
  description,
  libGL,
  libXcursor,
  libXi,
  libXrender,
  libgcc,
  libx11,
  libxcb,
  libxkbcommon,
  name,
  src,
  version,
  vulkan-loader,
  wayland,
}:

stdenv.mkDerivation {
  inherit src version;
  pname = name;
  nativeBuildInputs = [ autoPatchelfHook ];

  # Classes of dependency these binaries have. DT_NEEDED at build time:
  # libgcc_s.so.1 in all of them, libasound.so.2 in DeckCraft.
  buildInputs = [
    alsa-lib
    libgcc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r bin share $out/

    runHook postInstall
  '';

  # Upstream links only against glibc, everything else (wayland, xkbcommon,
  # X11, Vulkan) is dlopen'd by winit/wgpu at runtime.
  runtimeDependencies = [
    libGL
    libXcursor
    libXi
    libXrender
    libx11
    libxcb
    libxkbcommon
    vulkan-loader
    wayland
  ];

  sourceRoot = "${name}-${version}-linux-x86_64";

  meta = {
    inherit description;
    homepage = "https://getartcraft.com/apps/${name}";

    license = with lib.licenses; [
      mit
      asl20
    ];

    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = name;
  };
}
