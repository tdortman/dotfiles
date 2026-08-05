{
  lib,
  fetchurl,
  buildNpmPackage,
  fd,
  makeWrapper,
  nodejs,
  python311,
  ripgrep,
  runCommand,
  uv,
}:

let
  # Create a source with package-lock.json included
  srcWithLock = runCommand "prime-agent-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${version}/prime-agent-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
  '';
  version = versionData.version;
  versionData = lib.importJSON ./hashes.json;
in
buildNpmPackage {
  inherit version;
  pname = "prime-agent";
  src = srcWithLock;

  nativeBuildInputs = [
    makeWrapper
  ];

  npmDepsHash = versionData.npmDepsHash;

  # Wrap the Node entry point so node, fd, rg, uv, and python3.11 are on
  # PATH. uv and python311 satisfy the kernel bootstrap: prime-agent finds uv
  # on PATH instead of downloading it, and uv's "python install 3.11" is a
  # no-op because python3.11 is already available. The pi-heritage version
  # check and telemetry stay disabled.
  postInstall = ''
    rm -f "$out/bin/prime-agent"
    makeWrapper ${lib.getExe nodejs} "$out/bin/prime-agent" \
      --add-flags "$out/lib/node_modules/prime-agent/dist/bundle/cli.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          fd
          python311
          ripgrep
          uv
        ]
      } \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set PI_TELEMETRY 0
  '';

  doInstallCheck = true;
  # The release tarball ships a prebuilt dist/
  dontNpmBuild = true;
  makeCacheWritable = true;
  npmDepsFetcherVersion = 2;

  postInstallCheck = ''
    # The bundle imports zeromq, a native addon, at startup; loading it here
    # fails the build if the prebuilt addon is missing.
    ${lib.getExe nodejs} --input-type=module \
      --eval "import('$out/lib/node_modules/prime-agent/node_modules/zeromq/lib/index.js').then((m) => { if (typeof m.Dealer !== 'function') process.exit(1); })"
    # --version prints to stderr
    "$out/bin/prime-agent" --version 2>&1 | grep -q '^${version}$'
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "A self-improving RLM agent for coding workflows and long-running autonomous tasks";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "prime-agent";
  };
}
