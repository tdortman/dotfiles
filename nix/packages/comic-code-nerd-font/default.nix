{
  lib,
  bdf2psf,
  fontforge,
  requireFile,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "comic-code-nerd-font";
  version = "1";

  src = requireFile {
    hash = "sha256-fQODaygKrl8Vzxd3rj5mQwlZdzEg9gJ33maICxPgi/U=";
    message = "Add the Comic Code font to the store with: nix-store --add-fixed sha256 ~/.local/share/fonts/ComicCode/ComicCodeLigaturesNerdFontMono-Regular.otf";
    name = "ComicCodeLigaturesNerdFontMono-Regular.otf";
  };

  nativeBuildInputs = [
    bdf2psf
    fontforge
  ];

  buildPhase = ''
    runHook preBuild
    fontforge -lang=ff -c 'Open($1); BitmapsAvail([32]); Generate($2, "bdf")' "$src" comic-code.
    bdf2psf --fb comic-code-32.bdf \
      ${bdf2psf}/share/bdf2psf/standard.equivalents \
      ${bdf2psf}/share/bdf2psf/ascii.set+${bdf2psf}/share/bdf2psf/linux.set+${bdf2psf}/share/bdf2psf/useful.set+:${bdf2psf}/share/bdf2psf/fontsets/Lat15.256 \
      256 comic-code-nerd-font.psf
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 comic-code-nerd-font.psf "$out/share/consolefonts/comic-code-nerd-font.psf"
    install -Dm644 "$src" "$out/share/fonts/opentype/ComicCodeLigaturesNerdFontMono-Regular.otf"
    runHook postInstall
  '';

  dontUnpack = true;

  meta = {
    description = "Comic Code font and bitmap font for the Linux console";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
