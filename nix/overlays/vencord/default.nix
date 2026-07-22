_:

final: prev: {
  vencord = (prev.master.vencord.override { pnpm_10 = prev.pnpm_11; }).overrideAttrs (
    finalAttrs: oldAttrs: {
      version = "1.14.17";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        rev = "4b9c27d905d6255141617546227a56073916ebd4";
        hash = "sha256-dhBD/xlgf0VXVEP6I5kB6wmyJz7k8Epy1m8mHKhZuqs=";
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
