{
  lib,
  pkgs,
  ...
}:

let
  mkVethRunner =
    {
      name,
      logPrefix ? name,
      defaultInterface,
      disableIPv6 ? true,
      dropNonInterfaceForward ? true,
    }:
    let
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
          pkgs.iproute2
          pkgs.nftables
          pkgs.coreutils
          pkgs.util-linux
          pkgs.procps
          pkgs.gnugrep
          pkgs.socat
        ];
        text = setupText;
      };

      runPackage = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [
          pkgs.iproute2
          pkgs.coreutils
          pkgs.util-linux
          setupPackage
        ];
        text = runText;
      };
    in
    {
      inherit setupPackage runPackage;
    };

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
          pkgs.util-linux
          pkgs.systemd
        ];
        text = runText;
      };
    };
in
{
  options.interface-run.lib = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    readOnly = true;
  };

  config.interface-run.lib = {
    inherit mkVethRunner mkDirectRunner;
  };
}
