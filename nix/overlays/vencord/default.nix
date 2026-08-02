_:

final: prev: {
  # vencord = prev.master.vencord.overrideAttrs (
  #   finalAttrs: oldAttrs: {
  #     version = "1.15.0";

  #     src = prev.fetchFromGitHub {
  #       owner = "Vendicated";
  #       repo = "Vencord";
  #       rev = "v${finalAttrs.version}";
  #       hash = "sha256-z3EY/nc9pHPjuMteY8ubYM3sqgjASznEG6B1U4mNCU4=";
  #     };

  #     pnpmDeps = prev.fetchPnpmDeps {
  #       inherit (finalAttrs)
  #         pname
  #         src
  #         ;

  #       fetcherVersion = 4;
  #       hash = "sha256-JmTSfUVHsMG0TcOwXkZWinRxpONZagtwKzESd8Q4LlQ=";
  #       pnpm = prev.pnpm_11;
  #     };
  #   }
  # );
  inherit (final.master) vencord;
}
