{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hdr;

  hdr-disable-script = pkgs.writeShellApplication {
    name = "hdr-disable";
    runtimeInputs = [ hdr-toggle-script ];

    text = ''
      exec hdr-toggle disable "$@"
    '';
  };

  hdr-enable-script = pkgs.writeShellApplication {
    name = "hdr-enable";
    runtimeInputs = [ hdr-toggle-script ];

    text = ''
      exec hdr-toggle enable "$@"
    '';
  };

  hdr-toggle-script = pkgs.writeShellApplication {
    name = "hdr-toggle";

    runtimeInputs = with pkgs; [
      jq
      kdePackages.libkscreen
    ];

    text = scriptText;
  };

  # Read the script and substitute config values
  scriptText =
    builtins.replaceStrings
      [
        "@defaultOutput@"
        "@defaultIccProfile@"
      ]
      [
        cfg.defaultOutput
        cfg.defaultIccProfile
      ]
      (builtins.readFile ./hdr-toggle.sh);
in

{
  options.hdr = {
    enable = lib.mkEnableOption "KDE Plasma HDR toggling support";

    package = lib.mkOption {
      type = lib.types.package;
      default = hdr-toggle-script;
      defaultText = lib.literalExpression "hdr-toggle-script";

      description = ''
        The main hdr-toggle package to use.
      '';
    };

    defaultIccProfile = lib.mkOption {
      type = lib.types.str;
      example = "/home/user/.local/share/icc/my-display-profile.icc";
      default = "";

      description = ''
        Default ICC profile path to apply when HDR is disabled.
        Leave empty to skip ICC profile application.
      '';
    };

    defaultOutput = lib.mkOption {
      type = lib.types.str;
      example = "HDMI-A-1";
      default = "DP-1";

      description = ''
        Default display output to use when no output is specified.
        Use 'kscreen-doctor -o' to list available outputs.
      '';
    };

    extraScripts = lib.mkEnableOption "extra helper scripts (hdr-enable, hdr-disable)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.vulkan-hdr-layer-kwin6
    ]
    ++ lib.optionals cfg.extraScripts [
      hdr-enable-script
      hdr-disable-script
    ]
    ++ (
      let
        mpv-hdr-auto-script = pkgs.writeShellApplication {
          name = "mpv-hdr-auto";

          runtimeInputs = [
            hdr-toggle-script
            mpv-hdr-script
          ];

          text = ''
            hdr-toggle enable
            mpv-hdr "$@"
            hdr-toggle disable
          '';
        };
        mpv-hdr-script = pkgs.writeShellApplication {
          name = "mpv-hdr";
          runtimeInputs = [ pkgs.mpv ];

          text = ''
            ENABLE_HDR_WSI=1 mpv           \
              --vo=gpu-next                \
              --target-colorspace-hint     \
              --gpu-api=vulkan             \
              --gpu-context=waylandvk "$@"
          '';
        };
      in
      [
        mpv-hdr-script
        mpv-hdr-auto-script
      ]
    );
  };
}
