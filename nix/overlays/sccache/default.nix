_:

final: prev: {
  sccache = prev.sccache.overrideAttrs (oldAttrs: {
    # nixpkgs appends a lowercase `compiler-bindir = …` line to `nvcc.profile`,
    # which `nvcc --dryrun` echoes as `compiler-bindir=…`. sccache's env regex
    # only accepts `[_A-Z]+` keys, so that line is parsed as a subcommand and
    # sccache fails with "cannot find binary path".
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace src/compiler/nvcc.rs \
        --replace-fail 'r"^([_A-Z]+)=(.*)$"' 'r"^([\w.-]+)=(.*)$"'
    '';
  });
}
