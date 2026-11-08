_:

final: prev: {
  vencord = final.master.vencord.overrideAttrs (
    finalAttrs: _: {
      version = "1.15.16";

      src = prev.fetchFromGitHub {
        owner = "Vendicated";
        repo = "Vencord";
        tag = "v${finalAttrs.version}";
        hash = "sha256-aUJubLJpyLAZWiOezqFxPY6oVPgWVPQpajFqrJvrO9U=";
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
        hash = "sha256-HS8uZNepvDefjrsG3buVLFCVv7sHvazcwdpcT3EQ/78=";
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
