_:

final: prev: {
  vencord = (prev.master.vencord.override { pnpm_10 = prev.pnpm_11; }).overrideAttrs (
    finalAttrs: oldAttrs: {
      version = "1.15.0";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        rev = "v${finalAttrs.version}";
        hash = "sha256-z3EY/nc9pHPjuMteY8ubYM3sqgjASznEG6B1U4mNCU4=";
      };

      patches = [ ./fix-deps.patch ];

      pnpmDeps = prev.fetchPnpmDeps {
        inherit (finalAttrs)
          pname
          src
          patches
          postPatch
          ;

        fetcherVersion = 4;
        hash = "sha256-JmTSfUVHsMG0TcOwXkZWinRxpONZagtwKzESd8Q4LlQ=";
        pnpm = prev.pnpm_11;
      };

      postPatch = ''
        substituteInPlace packages/vencord-types/package.json \
          --replace-fail '"@types/react": "18.3.1"' '"@types/react": "19.1.0"'
      '';
    }
  );
  # inherit (final.master) vencord;
}
