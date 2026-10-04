{
  lib,
  stdenv,
  autoPatchelfHook,
  bubblewrap,
  desktop-file-utils,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
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
  python3,
  requireFile,
  vulkan-loader,
  wayland,
  webkitgtk_4_1,
  xdg-utils,
  zenity,
  # Embedded font PostScript name (e.g. "Geist-Regular") -> replacement font
  # file, patched into the binary at build time.
  fontReplacements ? { },
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tern";
  version = "0.4.5";

  src = requireFile {
    url = "https://build.stencil.so/tern";
    hash = "sha256-+TU0GutIi4QGCsLC1syAB/IcdRe1orFfo+dMr+qmq/0=";
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

    # Disables the per-launch ~/.local/bin/tern link and desktop file, which
    # point at this store path, and swaps in fontReplacements.
    ${python3.interpreter} ${./patch-binary.py} tern ${
      lib.escapeShellArgs (lib.mapAttrsToList (name: font: "${name}=${font}") fontReplacements)
    }

    install -Dm755 tern $out/lib/tern/tern

    # The fonts are copied into the binary; referencing them keeps requireFile
    # fonts in the store so later rebuilds don't need them re-added.
    mkdir -p $out/nix-support
    echo ${lib.escapeShellArg (lib.concatStringsSep "\n" (lib.attrValues fontReplacements))} \
      > $out/nix-support/replacement-fonts

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

    # Only the main launcher may claim windows; the hidden MIME handler
    # otherwise competes with it for Plasma taskbar grouping.
    desktop-file-edit --remove-key=StartupWMClass \
      $out/share/applications/so.stencil.tern.open.desktop

    desktop-file-edit \
      --set-generic-name="Terminal Emulator" \
      --set-comment=${lib.escapeShellArg finalAttrs.meta.description} \
      --add-category=System \
      --add-category=TerminalEmulator \
      $out/share/applications/so.stencil.tern.desktop
  '';

  # strip rewrites the ELF from its section headers, dropping the font
  # segment, which has none.
  dontStrip = true;

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
