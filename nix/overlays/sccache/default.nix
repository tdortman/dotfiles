_:

final: prev: {
  sccache = prev.sccache.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      # nixpkgs wraps nvcc with --compiler-bindir, which --dryrun echoes as the
      # lowercase `compiler-bindir=` line that sccache's `[_A-Z]+` env regex
      # rejects ("cannot find binary path"). CTK 13.x also emits `--simt-only`
      # between cicc's input and `-o`, breaking sccache's fixed input offsets.
      ./nvcc-dryrun-compat.patch
      ./cicc-input-offset.patch
    ];
  });
}
