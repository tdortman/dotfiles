{ ... }:

final: prev: {
  vencord = prev.vencord.overrideAttrs (
    finalAttrs: oldAttrs: {
      version = "1.14.10";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        rev = "v${finalAttrs.version}";
        hash = "sha256-+P0FF7PIJ+z0jBMwQM2JR5d1c05E8EOjUI9j7mAWddQ=";
      };

      pnpmDeps = prev.fetchPnpmDeps {
        inherit (finalAttrs)
          pname
          src
          patches
          postPatch
          ;

        pnpm = prev.pnpm_10;
        fetcherVersion = 2;
        hash = "sha256-GiUV2x8i7ewzn66v5wBUq67oNvrxZzOsh5TuQUtpJNQ=";
      };
    }
  );
}
