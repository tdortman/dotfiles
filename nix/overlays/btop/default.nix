_:

final: prev: {
  btop = prev.btop.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./intel-discrete-pmu.patch
      ./intel-hwmon.patch
      ./intel-vram.patch
      ./gpu-metrics-display.patch
      ./intel-extra-sensors.patch
    ];
  });
}
