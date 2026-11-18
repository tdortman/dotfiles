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
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "stencil-hq";
    repo = "ovnfs";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HuovVdxpSs5nHeampw8uRdl6eQmke9ZLyd7YfpvrHcw=";
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

    # Where setxattr fails (Nix's sandbox filter returns ENOTSUP) the upper keeps
    # identities in a `.wh..wh.ids` table, which is overlay metadata, but `upperEmpty`
    # counts it as a change: every checkout reads as dirty and folder attaches refuse.
    substituteInPlace checkout/operations.go \
      --replace-fail 'p == ".wh..wh.work" ||' 'p == ".wh..wh.work" || p == ".wh..wh.ids" ||'
  '';

  nativeBuildInputs = [
    installAgentSkills
    installShellFiles
  ];

  vendorHash = "sha256-BBC1CkTN/7WDqMX0+L9GuSNIogKxKamBSuY3TQwIC9Q=";
  env.CGO_ENABLED = 0;

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

  # nix-update prefetches goModules with outputHash = "", which defeats the hook's FOD guard.
  overrideModAttrs = _: { dontInstallAgentSkills = true; };
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
