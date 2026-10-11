{
  lib,
  fetchurl,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  python3,
  runCommand,
}:

let
  depsHash = "sha256-XuiMtaM/MPDkhjiHCr9dGC7WlsRBmsWepuNHRxAs3Nw=";
  lockHash = "sha256-tlXiEYl71yAy72kmG+hxDlA3se3neBBsj+9zAwetAFk=";
  # The registry tarball ships the built dist/ and the bridge sources, but not the
  # lockfile npm needs to resolve the runtime dependencies.
  src = runCommand "rea-agents-${version}-src" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
        hash = tarballHash;
      }
    } -C $out --strip-components=1
    cp ${
      fetchurl {
        url = "https://raw.githubusercontent.com/morluto/rea/rea-agents-${version}/package-lock.json";
        hash = lockHash;
      }
    } $out/package-lock.json
  '';
  tarballHash = "sha256-WesWBLjbdfUi1Kl1w2zmtKKtRl5DutFl+aj3KDkdubg=";
  version = "6.4.0";
in
buildNpmPackage {
  inherit src version;
  pname = "rea-agents";
  nativeBuildInputs = [ makeWrapper ];
  npmDepsHash = depsHash;

  postInstall = ''
    # The CLI shells out to node and to the Python bridges.
    wrapProgram $out/bin/rea --prefix PATH : ${
      lib.makeBinPath [
        nodejs
        python3
      ]
    }
  '';

  # dist/ is prebuilt in the published tarball, and its install hooks are not
  # needed to run the CLI.
  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "MCP server and CLI that give agents reverse-engineering tools for binaries, apps and runtime behaviour";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/rea-agents-${version}";
    license = lib.licenses.mit;

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    mainProgram = "rea";
  };
}
