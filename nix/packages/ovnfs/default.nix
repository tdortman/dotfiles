{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGo127Module,
  installAgentSkills,
  installShellFiles,
}:

buildGo127Module (finalAttrs: {
  pname = "ovnfs";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "stencil-hq";
    repo = "ovnfs";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Rzqs/ReUj4dhC5y9NSl7l/MxPdP5PjC38YHMYISGae0=";
  };

  # Go only stamps the module version into builds made by `go install pkg@version`, so a
  # build from source reports "(devel)" and `ovnfs send` would install the latest release on
  # the remote instead of this one. `ovnfs update` keeps the real build info and refuses.
  postPatch = ''
    cat > nix_version.go <<EOF
    package main

    import "runtime/debug"

    func nixBuildInfo() (*debug.BuildInfo, bool) {
    	bi, ok := debug.ReadBuildInfo()
    	if ok {
    		bi.Main.Version = "v${finalAttrs.version}"
    	}
    	return bi, ok
    }
    EOF
    substituteInPlace main.go send.go \
      --replace-fail '"runtime/debug"' "" \
      --replace-fail 'debug.ReadBuildInfo()' 'nixBuildInfo()'
  '';

  nativeBuildInputs = [
    installAgentSkills
    installShellFiles
  ];

  vendorHash = "sha256-BBC1CkTN/7WDqMX0+L9GuSNIogKxKamBSuY3TQwIC9Q=";
  env.CGO_ENABLED = 0;
  # nix-update prefetches goModules with outputHash = "", which defeats the hook's FOD guard.
  overrideModAttrs = _: { dontInstallAgentSkills = true; };

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd ovnfs \
      --bash <($out/bin/ovnfs completion bash -c) \
      --fish <($out/bin/ovnfs completion fish -c) \
      --zsh <($out/bin/ovnfs completion zsh -c)
  '';

  ldflags = [
    "-s"
    "-w"
  ];

  subPackages = [ "." ];

  meta = {
    description = "Isolated copy-on-write checkouts of any folder for coding agents";
    homepage = "https://github.com/stencil-hq/ovnfs";
    changelog = "https://github.com/stencil-hq/ovnfs/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "ovnfs";
  };
})
