{
  lib,
  stdenv,
  autoPatchelfHook,
  copyDesktopItems,
  glib-networking,
  libGL,
  libxkbcommon,
  linux-pam,
  makeDesktopItem,
  makeWrapper,
  openssl,
  requireFile,
  vulkan-loader,
  wayland,
  webkitgtk_4_1,
  wrapGAppsHook3,
  # Bundled font file name (e.g. "GeistVariable.ttf") -> replacement font
  # file. Tern loads these files directly, so the replacement keeps the
  # bundled name. Absolute strings outside the store become runtime symlinks.
  fontReplacements ? { },
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tern";
  version = "0.3.1";

  src = requireFile {
    url = "https://build.stencil.so/tern";
    hash = "sha256-BUNMF0XANeDBnsHTRYOJg0XzER/EUvUrlu1bhe1l7uA=";
    name = "Tern-${finalAttrs.version}-linux-x86_64.tar.gz";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    glib-networking
    openssl
    stdenv.cc.cc.lib
    webkitgtk_4_1
  ];

  installPhase = ''
    runHook preInstall

    # Tern installs ~/.local/bin/tern and a desktop file pointing at its own
    # store path whenever `assets` sits next to the binary. Keeping the assets
    # elsewhere disables that, so launches go through the system profile.
    install -Dm755 tern $out/lib/tern/tern
    mkdir -p $out/share/tern
    cp -r assets $out/share/tern/
    
    ${lib.concatMapAttrsStringSep "\n" (name: font: ''
      [[ -e $out/share/tern/assets/fonts/${lib.escapeShellArg name} ]] \
        || { echo "tern bundles no font named ${name}" >&2; exit 1; }
      ln -sf ${lib.escapeShellArg "${font}"} $out/share/tern/assets/fonts/${lib.escapeShellArg name}
    '') fontReplacements}

    makeWrapper $out/lib/tern/tern $out/bin/tern \
      "''${gappsWrapperArgs[@]}" \
      --set STENCIL_ASSETS $out/share/tern/assets

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      categories = [
        "System"
        "TerminalEmulator"
      ];

      comment = finalAttrs.meta.description;
      desktopName = "Tern";
      exec = "tern";
      genericName = "Terminal";
      icon = "utilities-terminal";
      name = "so.stencil.tern";
      startupWMClass = "so.stencil.tern";
    })
  ];

  # The wrapper below carries gappsWrapperArgs (TLS GIO module, GSettings
  # schemas) that WebKitGTK needs for browser blocks.
  dontWrapGApps = true;

  runtimeDependencies = [
    libGL
    libxkbcommon
    linux-pam
    vulkan-loader
    webkitgtk_4_1
    wayland
  ];

  meta = {
    description = "GPU-accelerated terminal emulator";
    homepage = "https://build.stencil.so/tern";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "tern";
  };
})
