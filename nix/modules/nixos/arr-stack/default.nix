{
  config,
  lib,
  ...
}:

let
  cfg = config.arr-stack;
in
{
  options.arr-stack = {
    enable = lib.mkEnableOption "the media automation stack (Sonarr, Prowlarr, FlareSolverr)";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for each service.";
    };

    extraBackupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths to include in backup list.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    services.prowlarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    services.flaresolverr = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };
  };
}
