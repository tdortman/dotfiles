_:

final: prev: {
  # vencord = prev.vencord.overrideAttrs (
  #   finalAttrs: oldAttrs: {
  #     version = "1.14.15";
  #     src = prev.fetchFromGitHub {
  #       owner = "Vendicated";
  #       repo = "Vencord";
  #       rev = "v${finalAttrs.version}";
  #       hash = "sha256-jQeLZa1rpKDkzWSpAqOa8snGRKLpv9xf9cwJ6hUwMzA=";
  #     };
  #     pnpmDeps = prev.fetchPnpmDeps {
  #       inherit (finalAttrs)
  #         pname
  #         src
  #         patches
  #         postPatch
  #         ;
  #       pnpm = prev.pnpm_10;
  #       fetcherVersion = 3;
  #       hash = "sha256-hk1rnNog5xvuIVI0M1ZJ5xrEuk0zcBiYsbROUycdi+A=";
  #     };
  #   }
  # );
  inherit (final.master) vencord;
}
