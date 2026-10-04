{
  lib,
  inputs,
  ...
}:

{
  # Not named default.nix, so it is not imported by every host. Hosts that want
  # the Plasma beta import this file: `imports` and `disabledModules` cannot
  # depend on config, so importing it is what opts in.
  imports = [
    "${inputs.nixpkgs-plasma-beta}/nixos/modules/services/desktop-managers/plasma6.nix"
  ];

  disabledModules = [ "services/desktop-managers/plasma6.nix" ];

  nixpkgs.overlays = lib.mkBefore [
    (final: prev: {
      kdePackages =
        (import inputs.nixpkgs-plasma-beta {
          inherit (prev) config;
          inherit (prev.stdenv.hostPlatform) system;
        }).kdePackages.overrideScope
          (
            kfinal: kprev: {
              kde-gtk-config = kprev.kde-gtk-config.overrideAttrs (oldAttrs: {
                # GTK can unload these modules while their file/theme callbacks
                # remain connected, crashing Discord when colors.css changes.
                # Keep their code resident; test-gtk-module-unload.py exercises
                # CSS reload after GTK clears its module list.
                patches = (oldAttrs.patches or [ ]) ++ [ ./gtk-modules-resident.patch ];
              });

              ktnef = kprev.ktnef.overrideAttrs (oldAttrs: {
                buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ kfinal.kcalutils ];
              });

              kwin = kprev.kwin.overrideAttrs (oldAttrs: {
                patches = (oldAttrs.patches or [ ]) ++ [
                  # Reworks how hardware colour pipeline blocks are assigned to
                  # planes and outputs in the DRM backend (drm_colorop.cpp,
                  # drm_output.cpp), for HDR through gamescope.
                  ./kwin-drm-color-pipeline.patch

                  # After resume KWin re-adds a GPU under its canonical node
                  # path, but caches the open handle under the path it was
                  # given, so a KWIN_DRM_DEVICES symlink misses the cache and
                  # logind rejects the second open as already taken.
                  ./kwin-drm-gpu-handle-key.patch

                  # Destroying output device mode resources early crashes
                  # plasmashell. Reverted upstream on master (KDE bug 525314).
                  ./kwin-revert-output-mode-destroy.patch
                ];
              });
            }
          );

      # `libreoffice-qt` is defined through whatever `kdePackages` resolves to,
      # so the beta scope drags in that snapshot's whole package set (boost,
      # openssl, qtbase). Those builds miss the binary cache and LibreOffice
      # compiles from source. Build it from the unmodified package set instead.
      libreoffice-qt =
        (import prev.path {
          inherit (prev.stdenv.hostPlatform) system;
          inherit (prev) config;
        }).libreoffice-qt;
    })
  ];
}
