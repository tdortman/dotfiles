{
  config,
  lib,
  pkgs,
  ...
}:

let
  canonicalLayout = layout: builtins.toJSON (removeAttrs layout [ "name" ]);
  cfg = config."display-layout";
  configFile = pkgs.writeText "display-layout-config.json" (
    builtins.toJSON {
      ddcEnable = cfg.ddc.enable;
      layouts = runtimeLayouts;
      login = cfg.loginLayout;
      managed = managedOutputs;
    }
  );
  connectorRegex = "^[A-Za-z]+(-[A-Za-z]+)?-[0-9]+(-[0-9]+)*$";
  ddcControlType = lib.types.submodule {
    options = {
      output = lib.mkOption {
        type = lib.types.strMatching connectorRegex;
        description = "DRM connector whose /sys ddc symlink resolves the DDC bus.";
      };

      gpu = lib.mkOption {
        type = lib.types.strMatching gpuRegex;
        description = "PCI address (domain:bus:device.function, lowercase as in sysfs) of the GPU exposing the DDC bus.";
      };
    };
  };
  displayLayout =
    assert lib.assertMsg (validationFailures == [ ]) (
      lib.concatMapStringsSep "\n" (a: a.message) validationFailures
    );
    pkgs.writeShellApplication {
      name = "display-layout";

      runtimeInputs = [
        pkgs.kdePackages.libkscreen
        pkgs.python3
      ]
      ++ lib.optionals cfg.ddc.enable [ pkgs.ddcutil ];

      text = ''exec python3 ${runtimeScript} ${configFile} "$@"'';
    };
  gpuByConnector = lib.groupBy (pair: pair.connector) gpuPairs;
  gpuPairs = builtins.concatLists (
    map (
      layout:
      map (o: {
        connector = o.output;
        gpu = o.gpu;
      }) layout.outputs
    ) cfg.layouts
  );
  gpuRegex = "^[0-9a-f]{4}:[0-9a-f]{2}:(0[0-9a-f]|1[0-9a-f])\\.[0-7]$";
  layoutNames = map (l: l.name) cfg.layouts;
  layoutType = lib.types.submodule {
    options = {
      disabledOutputs = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching connectorRegex);
        default = [ ];
        description = "Extra connectors disabled by this layout when present. Must not collide with this layout's outputs.";
      };

      name = lib.mkOption {
        type = lib.types.strMatching nameRegex;
        description = "Layout name used on the display-layout command line. Must match ^[A-Za-z0-9_-]+$, must not be cycle, help, -h, or --help, and must be unique across layouts.";
      };

      outputs = lib.mkOption {
        type = lib.types.nonEmptyListOf outputType;
        description = "Outputs in left-to-right placement order. The primary output gets priority 1, other outputs get priorities 2..N in list order. Mark exactly one output primary per layout. All listed outputs are required: a disconnected output fails the layout before any change.";
      };
    };
  };
  managedOutputs = lib.unique (
    builtins.concatLists (
      map (layout: map (o: o.output) layout.outputs ++ layout.disabledOutputs) cfg.layouts
    )
  );
  nameRegex = "^[A-Za-z0-9_-]+$";
  outputType = lib.types.submodule {
    options = {
      input = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 255);
        default = null;
        description = "Monitor VCP 60 input value selected via DDC when this output is connected. Null leaves the monitor input alone.";
      };

      output = lib.mkOption {
        type = lib.types.strMatching connectorRegex;
        description = "DRM connector for this output (see kscreen-doctor -o, e.g. DP-1 or HDMI-A-5). Unique per layout because kscreen-doctor addresses outputs by name.";
      };

      ddcControl = lib.mkOption {
        type = lib.types.nullOr ddcControlType;
        default = null;
        description = "GPU/connector resolving the fixed DDC I2C bus via /sys/bus/pci/devices. Defaults to this output's own GPU/connector. Needed when only one GPU path exposes a DDC symlink.";
      };

      gpu = lib.mkOption {
        type = lib.types.strMatching gpuRegex;
        description = "PCI address (domain:bus:device.function, lowercase as in sysfs, e.g. 0000:07:00.0) of the GPU driving this output. Build only checks BDF syntax; ownership is validated at runtime via sysfs.";
      };

      position = lib.mkOption {
        type = lib.types.nullOr positionType;
        default = null;
        description = "Explicit logical position overriding automatic placement. Automatic x accumulates logical widths of all preceding connected outputs; automatic y bottom-aligns against the tallest connected output.";
      };

      primary = lib.mkEnableOption "making this output the primary display";
    };
  };
  positionType = lib.types.submodule {
    options = {
      x = lib.mkOption {
        type = lib.types.ints.unsigned;
        description = "Explicit nonnegative logical x position, overriding automatic row placement.";
      };

      y = lib.mkOption {
        type = lib.types.ints.unsigned;
        description = "Explicit nonnegative logical y position, overriding automatic bottom alignment.";
      };
    };
  };
  reservedNames = [
    "cycle"
    "help"
    "-h"
    "--help"
  ];
  # Effective DDC source resolved at build time so the runtime just uses it.
  runtimeLayouts = map (layout: {
    disabledOutputs = layout.disabledOutputs;
    name = layout.name;

    outputs = map (output: {
      input = output.input;
      output = output.output;
      ddcGpu = if output.ddcControl == null then output.gpu else output.ddcControl.gpu;
      ddcOutput = if output.ddcControl == null then output.output else output.ddcControl.output;
      gpu = output.gpu;
      position = output.position;
      primary = output.primary;
    }) layout.outputs;
  }) cfg.layouts;
  runtimeScript = pkgs.writeTextFile {
    name = "display-layout.py";
    text = builtins.readFile ./display-layout.py;
  };
  # Shared build-time validation: referenced by both config.assertions and the
  # displayLayout package assert below, so an invalid config fails the package
  # build itself, not just the NixOS toplevel.
  validation = [
    {
      assertion = !builtins.any (layout: builtins.elem layout.name reservedNames) cfg.layouts;
      message = "display-layout.layouts names must not be cycle, help, -h, or --help.";
    }
    {
      assertion = builtins.length layoutNames == builtins.length (lib.unique layoutNames);
      message = "display-layout.layouts names must be unique.";
    }
    {
      assertion = builtins.all (
        layout:
        let
          connectors = map (o: o.output) layout.outputs;
        in
        builtins.length connectors == builtins.length (lib.unique connectors)
      ) cfg.layouts;

      message = "display-layout.layouts outputs must be unique within each layout since kscreen-doctor addresses outputs by name.";
    }
    {
      assertion = builtins.all (
        layout:
        let
          owned = map (o: o.output) layout.outputs ++ layout.disabledOutputs;
        in
        builtins.length owned == builtins.length (lib.unique owned)
        && builtins.length layout.disabledOutputs == builtins.length (lib.unique layout.disabledOutputs)
      ) cfg.layouts;

      message = "display-layout.layouts outputs must not collide with their own disabledOutputs, which must be unique.";
    }
    {
      assertion = builtins.all (
        connector: builtins.length (lib.unique (map (pair: pair.gpu) gpuByConnector.${connector})) == 1
      ) (builtins.attrNames gpuByConnector);

      message = "display-layout.layouts must use a consistent gpu for the same connector across layouts.";
    }
    {
      assertion =
        let
          forms = map canonicalLayout runtimeLayouts;
        in
        builtins.length forms == builtins.length (lib.unique forms);

      message = "display-layout.layouts must not contain duplicate identical layouts.";
    }
    {
      assertion = builtins.all (
        layout: builtins.length (builtins.filter (o: o.primary) layout.outputs) == 1
      ) cfg.layouts;

      message = "display-layout.layouts must have exactly one primary output per layout.";
    }
    {
      assertion = builtins.elem cfg.loginLayout layoutNames;
      message = "display-layout.loginLayout must match one of layouts names.";
    }
  ];
  validationFailures = builtins.filter (a: !a.assertion) validation;
in
{
  options.display-layout = {
    enable = lib.mkEnableOption "full display layouts with kscreen-doctor and optional DDC input switching";
    ddc.enable = lib.mkEnableOption "monitor input switching via ddcutil before applying the kscreen layout";

    layouts = lib.mkOption {
      type = lib.types.nonEmptyListOf layoutType;
      description = "Ordered full-display layouts cycled by display-layout (at least one). Each layout covers all physical displays. Cycle compares the full live state against layouts in order with wraparound. Build only checks syntax and consistency; physical validation is runtime only.";
    };

    loginLayout = lib.mkOption {
      type = lib.types.str;
      description = "Layout applied at login and as the cycle fallback when no layout matches the live state. Must match one of layouts names.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = validation;
    environment.systemPackages = [ displayLayout ];
    hardware.i2c.enable = lib.mkIf cfg.ddc.enable true;
    system.build.displayLayout = displayLayout;

    systemd.user.services.plasma-login-layout = {
      description = "Apply declarative display layout at Plasma login";
      before = [ "plasma-login.service" ];
      after = [ "plasma-login-kwin_wayland.service" ];
      wantedBy = [ "plasma-login-wayland.target" ];
      partOf = [ "plasma-login-wayland.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe displayLayout} ${cfg.loginLayout}";
      };
    };
  };
}
