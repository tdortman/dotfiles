{
  lib,
  pkgs,
  ...
}:

let
  mkDirectRunner =
    {
      name,
      namespace,
      logPrefix ? name,
      startUnits ? [ ],
    }:
    let
      runText =
        builtins.replaceStrings
          [
            "@namespace@"
            "@logPrefix@"
            "@startUnits@"
          ]
          [
            namespace
            logPrefix
            (lib.concatStringsSep " " startUnits)
          ]
          (builtins.readFile ./direct-run.sh);
    in
    {
      runPackage = pkgs.writeShellApplication {
        inherit name;

        runtimeInputs = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.systemd
          pkgs.util-linux
        ];

        text = runText;
      };
    };

  mkVethRunner =
    {
      defaultInterface,
      name,
      disableIPv6 ? true,
      dropNonInterfaceForward ? true,
      logPrefix ? name,
    }:
    let
      runPackage = pkgs.writeShellApplication {
        inherit name;

        runtimeInputs = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.util-linux
          setupPackage
        ];

        text = runText;
      };
      runText =
        builtins.replaceStrings
          [
            "@defaultInterface@"
            "@logPrefix@"
          ]
          [
            defaultInterface
            logPrefix
          ]
          (builtins.readFile ./veth-run.sh);
      setupPackage = pkgs.writeShellApplication {
        name = "${name}-setup";

        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
          pkgs.nftables
          pkgs.procps
          pkgs.socat
          pkgs.util-linux
        ];

        text = setupText;
      };
      setupText =
        builtins.replaceStrings
          [
            "@defaultInterface@"
            "@disableIPv6@"
            "@dropNonInterfaceForward@"
            "@logPrefix@"
          ]
          [
            defaultInterface
            (if disableIPv6 then "true" else "false")
            (if dropNonInterfaceForward then "true" else "false")
            logPrefix
          ]
          (builtins.readFile ./veth-setup.sh);
    in
    {
      inherit runPackage setupPackage;
    };
in
{
  options.interface-run.lib = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    readOnly = true;
  };

  config.interface-run.lib = {
    inherit mkDirectRunner mkVethRunner;
  };
}
