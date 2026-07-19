{
  lib,
  fetchurl,
  appimageTools,
}:

appimageTools.wrapType2 rec {
  pname = "shiru";
  version = "6.7.1";

  src = fetchurl {
    url = "https://github.com/RockinChaos/Shiru/releases/download/v${version}/linux-Shiru-v${version}.AppImage";
    sha256 = "sha256-ol/9fdRqGIFKhNq2Va0cUhyPIrSX9PCld2cU2BnQ+ng=";
  };

  extraInstallCommands =
    let
      extracted = appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      # Install desktop file
      install -Dm644 ${extracted}/${pname}.desktop $out/share/applications/${pname}.desktop

      # Point desktop file to wrapped binary
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun %U' 'Exec=${pname} --no-sandbox %U'

      # Install icon
      install -Dm644 ${extracted}/usr/share/icons/hicolor/512x512/apps/${pname}.png \
        $out/share/icons/hicolor/512x512/apps/${pname}.png
    '';

  meta = with lib; {
    description = "Manage your personal media library, organize your collection, and stream your content in real time, no waiting required!";
    homepage = "https://github.com/RockinChaos/Shiru";
    license = licenses.gpl3;
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
