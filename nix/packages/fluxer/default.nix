{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeWrapper,
  artifacts ? {
    aarch64-linux = {
      url = "https://api.fluxer.app/dl/desktop/stable/linux/arm64/fluxer-stable-${version}-arm64.AppImage";
      hash = "sha256-wxLNekbw3E0YPcC27COWtp8VphKmBB9bF2dp7lnjPf8=";
    };

    x86_64-linux = {
      url = "https://api.fluxer.app/dl/desktop/stable/linux/x64/fluxer-stable-${version}-x86_64.AppImage";
      hash = "sha256-GdoBK+Z/d2quEIY8INM4IQy5tzzIBBM+3CgJXQn0qAw=";
    };
  },
  middleClickScroll ? true,
  version ? "0.0.8",
}:

let
  appimageContents = appimageTools.extractType2 {
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
      --replace-fail "Exec=AppRun --no-sandbox %U" \
                     "Exec=$out/bin/${pname} %U"

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
