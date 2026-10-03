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
  python3,
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
  version = "0.4.0";

  src = requireFile {
    url = "https://build.stencil.so/tern";
    hash = "sha256-yKJJGA7cOXx4Noa6ITnyKKns5tZwgAHapOirKS5J7is=";
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

    ${python3.interpreter} - <<'PY'
    import os
    import struct
    import zlib
    from pathlib import Path

    data = Path("tern").read_bytes()
    for size in (16, 32, 48, 64, 128, 256, 512, 1024):
        header = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR" + struct.pack(">II", size, size)
        assert data.count(header) == 1, f"Expected one {size}x{size} Tern icon"
        start = data.index(header)
        end = start + 8
        while True:
            length, kind = struct.unpack_from(">I4s", data, end)
            crc = zlib.crc32(data[end + 4:end + 8 + length])
            assert crc == struct.unpack_from(">I", data, end + 8 + length)[0], "Invalid PNG chunk"
            end += length + 12
            if kind == b"IEND":
                break
        icon = Path(os.environ["out"]) / f"share/icons/hicolor/{size}x{size}/apps/so.stencil.tern.png"
        icon.parent.mkdir(parents=True, exist_ok=True)
        icon.write_bytes(data[start:end])
    PY

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
      icon = "so.stencil.tern";
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
