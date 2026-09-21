_:

final: prev: {
  gamescope = prev.gamescope.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ final.libgbm ];

    patches = (oldAttrs.patches or [ ]) ++ [
      ./linux-dmabuf-v6.patch
      ./wayland-output-pool.patch
      ./gbm-scanout-output.patch
    ];
  });
}
