{
  lib,
  fetchurl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "jadx-headless-mcp";
  version = "0.7.1";

  # REA audits this release jar by SHA-256 (release v0.7.1, source commit
  # 5844800a486d2248fa949b74c9896285f5b54de2), so the digest is load bearing.
  src = fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v${finalAttrs.version}/jadx-headless-mcp-${finalAttrs.version}-all.jar";
    hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
  };

  installPhase = ''
    runHook preInstall

    install -Dm444 $src $out/share/java/jadx-headless-mcp.jar

    runHook postInstall
  '';

  dontUnpack = true;

  meta = {
    description = "Headless MCP server for Android APK static analysis, built on jadx-core";
    homepage = "https://github.com/1013503897/jadx-headless-mcp";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
})
