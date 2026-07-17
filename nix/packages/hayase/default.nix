{
  lib,
  appimageTools,
  fetchurl,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
appimageTools.wrapType2 rec {
  pname = "hayase";
  version = source.version;

  src = fetchurl {
    inherit (source) url hash;
  };

  extraInstallCommands =
    let
      extracted = appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      install -Dm644 ${extracted}/${pname}.desktop $out/share/applications/${pname}.desktop

      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} --no-sandbox %U'

      install -d "$out/share/icons"
      cp -r "${extracted}/usr/share/icons/." "$out/share/icons/"
    '';

  meta = with lib; {
    description = "A bring-your-own-content torrent streaming client";
    homepage = "https://hayase.watch";
    license = licenses.bsl11;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
