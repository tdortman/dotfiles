{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeWrapper,
  artifacts ? {
    aarch64-linux = {
      url = "https://pkgs.fluxer.com/desktop/stable/linux/arm64/Fluxer-${version}-linux-arm64.AppImage";
      hash = "sha256-WD/KyJN1hRlfk3hNOFSAbtnXgDFd8uvm3o/GlgI6rhQ=";
    };

    x86_64-linux = {
      url = "https://pkgs.fluxer.com/desktop/stable/linux/x64/Fluxer-${version}-linux-x86_64.AppImage";
      hash = "sha256-13t72xKZEbVpdV5oLuUeDc87KDRMFX+uXkpr52sEPvs=";
    };
  },
  middleClickScroll ? true,
  version ? "2026.1001.230522",
}:

let
  appimageContents = appimageTools.extract {
    inherit pname src version;
  };
  artifact = artifacts.${system} or (throw "Unsupported system: ${system}");
  pname = "fluxer";
  src = fetchurl artifact;
  system = stdenv.hostPlatform.system;
  wrapperArgs = [
    "--add-flags"
    "--no-sandbox"
  ]
  ++ lib.optionals middleClickScroll [
    "--add-flags"
    "--enable-blink-features=MiddleClickAutoscroll"
  ];

in
appimageTools.wrapType2 {
  inherit pname src version;
  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/*.desktop \
      $out/share/applications/fluxer.desktop

    substituteInPlace $out/share/applications/fluxer.desktop \
      --replace-fail "Exec=AppRun %U" \
                     "Exec=$out/bin/${pname} %U" \
      --replace-fail 'Exec="/opt/Fluxer/fluxer"' \
                     "Exec=$out/bin/${pname}"

    cp -r ${appimageContents}/usr/share/icons $out/share/

    wrapProgram $out/bin/${pname} ${lib.escapeShellArgs wrapperArgs}
  '';

  meta = with lib; {
    description = "A free and open source instant messaging and VoIP platform built for friends, groups, and communities.";
    homepage = "https://fluxer.app";
    license = licenses.agpl3Only;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames artifacts;
    mainProgram = "fluxer";
  };
}
