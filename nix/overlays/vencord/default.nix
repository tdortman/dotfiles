_:

final: _: {
  # vencord = prev.vencord.overrideAttrs (
  #   finalAttrs: oldAttrs: {
  #     version = "1.14.11";
  #     src = prev.fetchFromGitHub {
  #       owner = "Vendicated";
  #       repo = "Vencord";
  #       rev = "v${finalAttrs.version}";
  #       hash = "sha256-Ylu1O4zvnVVEXzNQ5j1+Y2X54lVCyqVJLJa1Ngz+7aA=";
  #     };
  #     pnpmDeps = prev.fetchPnpmDeps {
  #       inherit (finalAttrs)
  #         pname
  #         src
  #         patches
  #         postPatch
  #         ;
  #       pnpm = prev.pnpm_10;
  #       fetcherVersion = 2;
  #       hash = "sha256-GiUV2x8i7ewzn66v5wBUq67oNvrxZzOsh5TuQUtpJNQ=";
  #     };
  #   }
  # );
  inherit (final.master) vencord;
}
