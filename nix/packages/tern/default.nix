{
  lib,
  stdenv,
  autoPatchelfHook,
  bubblewrap,
  desktop-file-utils,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  kdotool,
  libGL,
  libnotify,
  libsecret,
  libxkbcommon,
  linux-pam,
  makeWrapper,
  openssh,
  openssl,
  perf,
  pipewire,
  requireFile,
  vulkan-loader,
  wayland,
  webkitgtk_4_1,
  xdg-utils,
  zenity,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tern";
  version = "0.6.2";

  src = requireFile {
    url = "https://build.stencil.so/tern";
    hash = "sha256-SLlYBqviEef1EdkJ0hq9mF9k/a20+c3dBqrDCvAAPJc=";
    name = "Tern-${finalAttrs.version}-linux-x86_64.tar.gz";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    desktop-file-utils
    makeWrapper
  ];

  buildInputs = [
    openssl
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 tern $out/lib/tern/tern

    # Without the schemas GTK reports -1 DPI on Wayland, breaking WebKit page
    # geometry and font sizing; glib-networking is WebKit's TLS backend.
    # PATH supplies sandboxing, credentials, desktop integration and profiling.
    makeWrapper $out/lib/tern/tern $out/bin/tern \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          glib
          libnotify
          libsecret
          openssh
          perf
          xdg-utils
          zenity
        ]
      } \
      --prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules \
      --prefix XDG_DATA_DIRS : ${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}

    runHook postInstall
  '';

  # `tern register` executes the ELF, so patch it before the fixup phase.
  # Both desktop entries need the wrapper for WebKit and file dialogs.
  postInstall = ''
    autoPatchelf $out/lib/tern/tern

    HOME=$TMPDIR/home $out/lib/tern/tern register
    mkdir -p $out/share
    cp -r $TMPDIR/home/.local/share/{applications,icons} $out/share/
    rm -f $out/share/icons/hicolor/icon-theme.cache

    substituteInPlace $out/share/applications/so.stencil.tern{,.open}.desktop \
      --replace-fail 'Exec="'$out'/lib/tern/tern"' "Exec=$out/bin/tern"

    # Raise the running Plasma window before selecting the file tab.
    makeWrapper $out/bin/tern $out/bin/tern-open \
      --add-flags "open --tab" \
      --run ${lib.escapeShellArg ''
        if [[ "''${KDE_SESSION_VERSION:-}" == 6 ]]; then
          window=$(${lib.getExe' kdotool "kdotool"} search --limit 1 --class '^so\.stencil\.tern$') || exit $?
          if [[ -n $window ]]; then
            ${lib.getExe' kdotool "kdotool"} windowactivate "$window" || exit $?
          fi
        fi
      ''}

    # Only the main launcher may claim windows for Plasma taskbar grouping.
    # Reusing a window does not complete a new-window startup notification.
    desktop-file-edit \
      --set-key=Exec --set-value="$out/bin/tern-open %f" \
      --set-key=StartupNotify --set-value=false \
      --remove-key=StartupWMClass \
      $out/share/applications/so.stencil.tern.open.desktop

    desktop-file-edit \
      --set-generic-name="Terminal Emulator" \
      --set-comment=${lib.escapeShellArg finalAttrs.meta.description} \
      --add-category=System \
      --add-category=TerminalEmulator \
      $out/share/applications/so.stencil.tern.desktop
  '';

  runtimeDependencies = [
    libGL
    libxkbcommon
    linux-pam
    pipewire
    vulkan-loader
    wayland
    webkitgtk_4_1
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
