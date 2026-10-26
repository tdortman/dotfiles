_:

final: prev: {
  vencord = final.master.vencord.overrideAttrs (
    finalAttrs: _: {
      version = "1.15.13";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        tag = "v${finalAttrs.version}";
        hash = "sha256-YuzFkZafNJ0brt2S3gg+pm6xYXZEAjBkDH76cb0dmd8=";
      };

      pnpmDeps = prev.fetchPnpmDeps {
        inherit (finalAttrs)
          patches
          pname
          postPatch
          src
          ;

        fetcherVersion = 4;
        hash = "sha256-4dZTLwLoWnz6/svC6HH6SFuroYmPWDEpEAtByGzGHEw=";
        pnpm = final.master.pnpm_11;
      };
    }
  );

  # inherit (final.master) vencord;
}
