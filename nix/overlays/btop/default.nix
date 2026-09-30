_:

final: prev: {
  btop = prev.btop.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./intel-discrete-pmu.patch
      ./intel-hwmon.patch
      ./intel-vram.patch
      ./gpu-metrics-display.patch
      ./intel-extra-sensors.patch
      # Parse /proc/<pid>/stat after the last ')' instead of reusing a space
      # count from comm cached on first sight. Processes that rename
      # themselves to a name with spaces otherwise show start time as RSS.
      (final.fetchpatch2 {
        name = "btop-proc-stat-name-parse.patch";
        url = "https://github.com/aristocratos/btop/commit/524f5fef4ce7251172561ad90aa3f1d1a23813a5.patch";
        includes = [ "src/*" ];
        hash = "sha256-x7DzLMKTqUbjWOSWMGJkcaGIkgm04/SI7+bngXlKBfc=";
      })
    ];
  });
}
