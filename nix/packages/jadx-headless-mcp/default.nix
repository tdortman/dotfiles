{
  lib,
  fetchurl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "jadx-headless-mcp";
  version = "0.8.0";

  # REA audits this release jar by SHA-256 (release v0.8.0, source commit
  # e9e14f155db9ff7d8b5330c1e1247a0860721c30), so the digest is load bearing.
  src = fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v${finalAttrs.version}/jadx-headless-mcp-${finalAttrs.version}-all.jar";
    hash = "sha256-S5oBwjhFwSPCF4QBgtK18sJqfKIN7D0IgQsxD8gKI3I=";
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
