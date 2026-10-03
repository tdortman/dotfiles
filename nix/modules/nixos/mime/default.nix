{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.mime;
in
{
  options.custom.mime.librewolf.enable =
    lib.mkEnableOption "LibreWolf as default browser via XDG MIME associations";

  config = lib.mkIf cfg.librewolf.enable {
    environment.variables = {
      BROWSER = "${pkgs.librewolf}/bin/librewolf";
      DEFAULT_BROWSER = "${pkgs.librewolf}/bin/librewolf";
    };

    xdg.mime.defaultApplications = {
      "text/html" = "librewolf.desktop";
      "x-scheme-handler/about" = "librewolf.desktop";
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
    };
  };
}
