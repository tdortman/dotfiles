_:

_: prev: {
  libfprint = prev.libfprint.overrideAttrs (oldAttrs: {
    src = prev.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "depau";
      repo = "libfprint";
      rev = "elanmoc2-working";
      hash = "sha256-uYT1qQK5Hv4AcX9AT9jc36oygiOnpoVh7W4bdsiXWog=";
    };
    buildInputs = oldAttrs.buildInputs ++ [ prev.nss ];
  });
}
