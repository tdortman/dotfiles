{
  config,
  lib,
  ...
}:

let
  cfg = config.vpn-run;
  runners = config.interface-run.lib.mkVethRunner {
    inherit (cfg) defaultInterface disableIPv6;
    dropNonInterfaceForward = cfg.dropNonVpnForward;
    name = "vpn-run";
  };

  vpnRunSetup = runners.setupPackage;
  vpnRun = runners.runPackage;

in
{
  options.vpn-run = {
    enable = lib.mkEnableOption "vpn-run service for routing commands through a specific interface via a veth-isolated namespace";

    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      description = "vpn-run derivation for wrappers such as jgu-vpn-run.";
    };

    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;

      example = [
        "alice"
        "bob"
      ];

      default = [ ];
      description = "List of users allowed to use vpn-run without sudo password";
    };

    defaultInterface = lib.mkOption {
      type = lib.types.str;
      example = "wg0";
      default = "wg0";
      description = "Default network interface to route traffic through";
    };

    disableIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable IPv6 inside the network namespace to avoid leaks.";
    };

    dropNonVpnForward = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Drop forwarding from the namespace to any interface other than the chosen VPN interface.";
    };

    shellAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create a shell alias for vpn-run";
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      shellAliases = {
        vpn-run = lib.mkIf cfg.shellAlias "sudo -E vpn-run";
        vpn-run-down = lib.mkIf cfg.shellAlias "sudo vpn-run-setup -t";
      };

      systemPackages = [
        vpnRun
        vpnRunSetup
      ];
    };

    security.sudo.extraRules = lib.mkIf (cfg.allowedUsers != [ ]) [
      {
        commands = [
          {
            options = [
              "NOPASSWD"
              "SETENV"
            ];

            command = "${vpnRun}/bin/vpn-run";
          }
          {
            options = [
              "NOPASSWD"
              "SETENV"
            ];

            command = "/run/current-system/sw/bin/vpn-run";
          }
        ];

        users = cfg.allowedUsers;
      }
    ];

    users.groups.vpn-run = lib.mkIf (cfg.allowedUsers != [ ]) {
      members = cfg.allowedUsers;
    };

    vpn-run.package = vpnRun;
  };
}
