_:

final: prev: {
  vencord = final.master.vencord.overrideAttrs (
    finalAttrs: _: {
      version = "1.15.17";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        tag = "v${finalAttrs.version}";
        hash = "sha256-+dN4wAFNmYVDiEe0QStqrFBRFHBBRkApqbmhuvsLZZM=";
      };

      # nixpkgs' @types/react pin is upstream since 1.15.16
      patches = [ ];

      pnpmDeps = prev.fetchPnpmDeps {
        inherit (finalAttrs)
          patches
          pname
          postPatch
          src
          ;

        fetcherVersion = 4;
        hash = "sha256-/BoLLeKsftWv1bjWuND8967YGhqWEaCZZU6z/oa+0oM=";
        pnpm = final.master.pnpm_11;
      };

      postPatch = "";

      preBuild = ''
        mkdir -p src/userplugins
        cp -r ${./emojiPickerRefocus} src/userplugins/emojiPickerRefocus
      '';
    }
  );

  # inherit (final.master) vencord;
}
