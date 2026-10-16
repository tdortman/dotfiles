{
  lib,
  fetchurl,
  appimageTools,
}:

appimageTools.wrapType2 rec {
  pname = "shiru";
  version = "6.9.1";

  src = fetchurl {
    url = "https://github.com/RockinChaos/Shiru/releases/download/v${version}/linux-Shiru-v${version}.AppImage";
    sha256 = "sha256-5oBLb/7CjLeNTc1l/VFRZUmz07Fh0/lG9b4bNe6Lr0U=";
  };

  extraInstallCommands =
    let
      extracted = appimageTools.extract { inherit pname src version; };
    in
    ''
      # Install desktop file
      install -Dm644 -t $out/share/applications ${extracted}/*.desktop

      # Point desktop file to wrapped binary
      substituteInPlace $out/share/applications/com.github.rockinchaos.shiru.desktop \
        --replace-fail 'Exec=AppRun %U' 'Exec=${pname} --no-sandbox %U'

      cp -r ${extracted}/usr/share/icons $out/share/
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
