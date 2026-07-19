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

    extraBackupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths to include in backup list.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for each service.";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      flaresolverr = {
        inherit (cfg) openFirewall;
        enable = true;
      };

      prowlarr = {
        inherit (cfg) openFirewall;
        enable = true;
      };

      sonarr = {
        inherit (cfg) openFirewall;
        enable = true;
      };
    };
  };
}
