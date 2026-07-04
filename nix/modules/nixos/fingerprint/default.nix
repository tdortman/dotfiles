{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.fingerprint;
in
{
  options.fingerprint = {
    enable = lib.mkEnableOption "fingerprint scanning";

    fprintPkg = lib.mkPackageOption pkgs "fprintd" { };
    libfprintPkg = lib.mkPackageOption pkgs "libfprint" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.fprintPkg
      cfg.libfprintPkg
    ];
    services.fprintd.enable = true;

    services.fprintd.package = pkgs.fprintd.override {
      libfprint = cfg.libfprintPkg;
    };

    # If we want to manage fingerprints via the plasma GUI we need to allow this
    # At least with the elanmoc2 driver this seems to be necessary, idk about other drivers
    environment.etc."polkit-1/rules.d/45-fprintd.rules" =
      lib.mkIf config.services.desktopManager.plasma6.enable
        {
          text = ''
            polkit.addRule(function(action, subject) {
              if (action.id.match(/^net\.reactivated\.fprint\.device\./)) {
                return polkit.Result.YES;
              }
            });
          '';
          mode = "0644";
        };
  };
}
