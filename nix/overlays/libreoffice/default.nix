_:

final: prev: {
  # KDE Fusion (KF6) VCL plugin, running through XCB/XWayland instead of the
  # Qt Wayland plugin. `libreoffice-qt6` is an alias of this attribute, so
  # both names resolve to the wrapped build.
  libreoffice-qt = prev.libreoffice-qt.override {
    extraMakeWrapperArgs = [
      "--set"
      "QT_QPA_PLATFORM"
      "xcb"
      "--set"
      "SAL_USE_VCLPLUGIN"
      "kf6"
    ];
  };
}
