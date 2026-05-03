{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.vpn-run;

  scriptTextSetup =
    builtins.replaceStrings
      [
        "@defaultInterface@"
        "@vethHostAddress@"
        "@vethNsAddress@"
        "@disableIPv6@"
        "@dropNonVpnForward@"
      ]
      [
        cfg.defaultInterface
        cfg.vethHostAddress
        cfg.vethNsAddress
        (if cfg.disableIPv6 then "true" else "false")
        (if cfg.dropNonVpnForward then "true" else "false")
      ]
      (builtins.readFile ./vpn-run-setup.sh);

  scriptTextRun = builtins.replaceStrings [ "@defaultInterface@" ] [ cfg.defaultInterface ] (
    builtins.readFile ./vpn-run.sh
  );

  vpnRunSetup = pkgs.writeShellApplication {
    name = "vpn-run-setup";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.nftables
      pkgs.coreutils
      pkgs.util-linux
      pkgs.procps
      pkgs.gnugrep
      pkgs.socat
    ];
    text = scriptTextSetup;
  };

  vpnRun = pkgs.writeShellApplication {
    name = "vpn-run";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.coreutils
      pkgs.util-linux
      vpnRunSetup
    ];
    text = scriptTextRun;
  };

in
{
  options.vpn-run = {
    enable = lib.mkEnableOption "vpn-run service for routing commands through a specific interface via a veth-isolated namespace";

    defaultInterface = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
      description = "Default network interface to route traffic through";
      example = "wg0";
    };

    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users allowed to use vpn-run without sudo password";
      example = [
        "alice"
        "bob"
      ];
    };

    shellAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create a shell alias for vpn-run";
    };

    vethHostAddress = lib.mkOption {
      type = lib.types.str;
      default = "198.18.0.1/30";
      description = "Host-side veth address (CIDR). Keep a /30 or /31 to avoid conflicts.";
      example = "198.18.0.1/30";
    };

    vethNsAddress = lib.mkOption {
      type = lib.types.str;
      default = "198.18.0.2/30";
      description = "Namespace-side veth address (CIDR). Must be in the same subnet as vethHostAddress.";
      example = "198.18.0.2/30";
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
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      vpnRun
      vpnRunSetup
    ];

    environment.shellAliases = {
      vpn-run = lib.mkIf cfg.shellAlias "sudo -E vpn-run";
    };

    security.sudo.extraRules = lib.mkIf (cfg.allowedUsers != [ ]) [
      {
        users = cfg.allowedUsers;
        commands = [
          {
            command = "${vpnRun}/bin/vpn-run";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
          {
            command = "/run/current-system/sw/bin/vpn-run";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];

    users.groups.vpn-run = lib.mkIf (cfg.allowedUsers != [ ]) {
      members = cfg.allowedUsers;
    };
  };
}
