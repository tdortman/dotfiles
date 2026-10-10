{
  lib,
  stdenv,
  fetchurl,
  ghidra,
  openjdk21,
  python3Packages,
  unzip,
  writeShellApplication,
}:

let
  bridgeHash = "sha256-cZOaiQAJgmZkcgFm2PeG86LqJGD37/zYPHN1m6QkEzQ=";
  extension = stdenv.mkDerivation {
    inherit version;
    pname = "ghidra-mcp-extension";

    src = fetchurl {
      url = release "GhidraMCP-${version}.zip";
      hash = extensionHash;
    };

    nativeBuildInputs = [ unzip ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/ghidra/Ghidra/Extensions/GhidraMCP
      cp -r . $out/lib/ghidra/Ghidra/Extensions/GhidraMCP/

      # Ghidra writes a plugin lock file next to the extension; the store is read-only.
      touch $out/lib/ghidra/Ghidra/Extensions/GhidraMCP/.dbDirLock

      runHook postInstall
    '';

    meta = {
      description = "Ghidra plugin running the Ghidra MCP HTTP server";
      homepage = "https://github.com/bethington/ghidra-mcp";
      license = lib.licenses.asl20;
      platforms = ghidra.meta.platforms;
    };
  };
  # 6.0.0 is the newest release whose Ghidra extension is stamped for Ghidra
  # 12.1.2, which is what nixpkgs ships. Ghidra refuses to load an extension
  # built for another version, so bump this together with pkgs.ghidra.
  extensionHash = "sha256-hncx3ifVFDYyoBCUO5B6ZIXdVNDhlyni+F7p9pLJmHM=";
  # The extension jar also holds a headless server that drives Ghidra without a
  # GUI; it needs Ghidra's jars on the classpath because the extension bundles
  # none of them.
  ghidraHome = "${ghidra}/lib/ghidra";
  headless = writeShellApplication {
    name = "ghidra-mcp-headless";

    text = ''
      extension_jar=${lib.escapeShellArg "${extension}/lib/ghidra/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-${version}.jar"}
      ghidra_home=${lib.escapeShellArg ghidraHome}

      classpath="$extension_jar"
      for jar in "$ghidra_home"/Ghidra/{Framework,Features,Processors}/*/lib/*.jar; do
        classpath="$classpath:$jar"
      done

      exec ${lib.getExe openjdk21} \
        -Dghidra.home="$ghidra_home" \
        -Dapplication.name=GhidraMCP \
        -classpath "$classpath" \
        com.xebyte.headless.GhidraMCPHeadlessServer \
        "$@"
    '';
  };
  release = file: "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/${file}";
  version = "6.0.0";
in
python3Packages.buildPythonApplication {
  inherit version;
  pname = "ghidra-mcp";

  src = fetchurl {
    url = release "ghidra_mcp_bridge-${version}-py3-none-any.whl";
    hash = bridgeHash;
  };

  postInstall = ''
    ln -s ${headless}/bin/ghidra-mcp-headless $out/bin/ghidra-mcp-headless
  '';

  # starlette and uvicorn arrive with mcp.
  dependencies = [ python3Packages.mcp ];
  format = "wheel";
  pythonImportsCheck = [ "bridge_mcp_ghidra" ];

  passthru = {
    extension = extension;
    # Ghidra with the extension as a secondary application root, which is how the
    # Nix build finds plugins it cannot write into its own store path.
    ghidra = ghidra.withExtensions (_: [ extension ]);
  };

  meta = {
    description = "MCP bridge exposing Ghidra to AI agents, plus the matching Ghidra plugin";
    homepage = "https://github.com/bethington/ghidra-mcp";
    license = lib.licenses.asl20;
    platforms = ghidra.meta.platforms;
    mainProgram = "bridge-mcp-ghidra";
  };
}
