{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.audio;

  muteAudioInputs = pkgs.writeShellApplication {
    name = "mute-audio-inputs";
    runtimeInputs = [
      pkgs.jq
      pkgs.pipewire
      pkgs.wireplumber
    ];
    text = ''
      for _ in $(seq 1 20); do
        found=0

        while IFS= read -r id; do
          found=1
          wpctl set-mute "$id" 1 || true
        done < <(
          pw-dump Node | jq -r --argjson names '${builtins.toJSON cfg.mutedInputs}' '
            .[]
            | select(.info.props."media.class" == "Audio/Source")
            | select(.info.props."node.name" as $name | $names | index($name))
            | .id
          '
        )

        [ "$found" -eq 1 ] && exit 0
        sleep 0.5
      done
    '';
  };

  mkAppRoutingRules =
    categories:
    let
      categoryRules = lib.mapAttrsToList (
        categoryName: categoryConfig:
        let
          targetName = categoryName;

          nameRules = map (appName: {
            matches = [ { "application.name" = "~${appName}"; } ];
            actions.update-props."node.target" = targetName;
          }) categoryConfig.appNames;

          binaryRules = map (binary: {
            matches = [ { "application.process.binary" = binary; } ];
            actions.update-props."node.target" = targetName;
          }) categoryConfig.binaries;

        in
        nameRules ++ binaryRules
      ) categories;

    in
    lib.flatten categoryRules;

in
{
  options.audio = {
    enable = lib.mkEnableOption "the custom PipeWire audio configuration";

    input = lib.mkOption {
      type = lib.types.str;
      description = "The name of the hardware source (microphone) device.";
      example = "alsa_input.pci-0000_01_00.1.analog-stereo";
    };

    inputChannels = lib.mkOption {
      type = lib.types.enum [
        "mono"
        "stereo"
      ];
      description = ''
        Channel layout of the hardware input (audio.input).

        Mono sources are duplicated to stereo (FL+FR) before mic processing so
        stereo-only plugins and virtual inputs receive signal on both channels.
        Stereo sources are passed through without upmixing.
      '';
      example = "mono";
    };

    output = lib.mkOption {
      type = lib.types.str;
      description = "The name of the hardware sink (output) device.";
      example = "alsa_output.pci-0000_00_1f.3.analog-stereo";
    };

    mutedInputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hardware source node names to mute when PipeWire creates them.";
      example = [ "alsa_input.usb-046d_Brio_100_2602ZBR396W8-02.mono-fallback" ];
    };

    appCategories = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            limitThreshold = lib.mkOption {
              type = lib.types.float;
              default = -14.0;
              description = "Limiter threshold in dB for this category.";
            };

            appNames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of application names (regex patterns) to match";
              example = [
                "LibreWolf"
                "Firefox"
                "Chromium.*"
              ];
            };

            binaries = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of binary names to match";
              example = [
                "spotify"
                "vlc"
              ];
            };
          };
        }
      );
      description = "Application categories for audio routing and processing";
    };

    fallbackCategory = lib.mkOption {
      type = lib.types.enum (lib.attrNames cfg.appCategories);
      description = "Default category for applications that don't match any specific rules.";
    };

    micProcess = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "RNNoise-based microphone noise suppression";

          vadThreshold = lib.mkOption {
            type = lib.types.float;
            default = 50.0;
            description = "Voice Activity Detection (VAD) threshold percentage for RNNoise.";
            example = 75.0;
          };

          compressor = lib.mkOption {
            type = lib.types.submodule {
              options = {
                attackTime = lib.mkOption {
                  type = lib.types.float;
                  description = "Attack time (ms)";
                  example = 10.6;
                };
                releaseTime = lib.mkOption {
                  type = lib.types.int;
                  description = "Release time (ms)";
                  example = 500;
                };
                threshold = lib.mkOption {
                  type = lib.types.float;
                  description = "Threshold level (dB)";
                  example = -18.3;
                };
                ratio = lib.mkOption {
                  type = lib.types.float;
                  description = "Ratio (1:n)";
                  example = 4.0;
                };
                makeupGain = lib.mkOption {
                  type = lib.types.float;
                  description = "Makeup gain (dB)";
                  example = 5.9;
                };
              };
            };
            description = "Compressor options";
          };
        };
      };
      description = "Microphone processing options";
    };

    eq = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "a parametric equalizer on the main output";

          file = lib.mkOption {
            type = lib.types.str;
            example = "/path/to/parametric-eq.txt";
            description = "Absolute path to parametric EQ settings file generated by AutoEQ";
          };
        };
      };
      default = { };
      example = {
        enable = true;
        file = "/path/to/parametric-eq.txt";
      };
      description = "Equalizer options";
    };

  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      pkgs.qpwgraph
    ];

    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;

      extraLadspaPackages = [
        pkgs.ladspaPlugins
      ]
      ++ lib.optional cfg.micProcess.enable pkgs.rnnoise-plugin;
    };

    services.pipewire.wireplumber.extraConfig."99-alsa-rules" = {
      "monitor.alsa.rules" = [
        {
          matches = [ { "node.name" = cfg.output; } ];
          actions.update-props = {
            "api.alsa.period-num" = 32;
            "api.alsa.headroom" = 8192;
            "api.alsa.disable-tsched" = true;
          };
        }
        {
          matches = [ { "node.name" = cfg.input; } ];
          actions.update-props = {
            "api.alsa.period-num" = 32;
            "api.alsa.headroom" = 8192;
            "api.alsa.disable-tsched" = true;
          };
        }
      ];
    };

    systemd.user.services.mute-audio-inputs = lib.mkIf (cfg.mutedInputs != [ ]) {
      description = "Mute configured PipeWire audio inputs";
      wantedBy = [ "default.target" ];
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      wants = [ "wireplumber.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe muteAudioInputs;
      };
    };

    services.pipewire.extraConfig.pipewire-pulse."99-app-routing" = {
      "pulse.rules" = [
        {
          matches = [ { "application.name" = "~.*"; } ];
          actions.update-props."node.target" = cfg.fallbackCategory;
        }
      ]
      ++ (mkAppRoutingRules cfg.appCategories);
    };

    services.pipewire.extraConfig.pipewire."10-processing-and-linking" =
      let
        mkAppChain = categoryName: categoryConfig: {
          name = "libpipewire-module-filter-chain";
          args = {
            "capture.props" = {
              "node.name" = "${categoryName}";
              "node.description" = "${categoryName} (Raw)";
              "media.class" = "Audio/Sink";
              "audio.position" = "FL,FR";
            };
            "playback.props" = {
              "node.name" = "${categoryName}Processed";
              "node.description" = "${categoryName} (Processed)";
              "media.class" = "Audio/Source";
            };
            "filter.graph" = {
              nodes = [
                {
                  type = "ladspa";
                  plugin = "fast_lookahead_limiter_1913";
                  label = "fastLookaheadLimiter";
                  control = {
                    "Limit (dB)" = categoryConfig.limitThreshold;
                    "Release time (s)" = 0.1;
                  };
                }
              ];
            };
          };
        };

        mkMainLoopback = name: {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "${name} ➜ Main";
            "capture.props"."node.target" = "${name}Processed";
            "playback.props"."node.target" = if cfg.eq.enable then "MainEQ" else cfg.output;
          };
        };

        appChains = lib.mapAttrsToList mkAppChain cfg.appCategories;
        mainLoopbacks = map (name: mkMainLoopback name) (lib.attrNames cfg.appCategories);

        inputIsMono = cfg.inputChannels == "mono";

        stereoStreamProps = {
          "audio.position" = "FL,FR";
        };

        monoStreamProps = {
          "audio.channels" = 1;
          "audio.position" = "[ MONO ]";
        };

        # Upmix at the processed source output; loopback channelmix is unreliable for MONO→FL/FR.
        monoToStereoOutputProps = {
          "audio.channels" = 2;
          "audio.position" = "FL,FR";
          "channelmix.upmix" = true;
          "channelmix.upmix-method" = "simple";
          "channelmix.normalize" = false;
          "stream.dont-remix" = false;
        };

        micCaptureStreamProps = if inputIsMono then monoStreamProps else stereoStreamProps;

        # Stereo compressor output is already FL/FR; upmix only for direct HW passthrough.
        micFilterPlaybackStreamProps = stereoStreamProps;

        micPassthroughPlaybackStreamProps =
          if inputIsMono then monoToStereoOutputProps else stereoStreamProps;

        rnnoiseLabel = if inputIsMono then "noise_suppressor_mono" else "noise_suppressor_stereo";

        compressorLinks =
          if inputIsMono then
            [
              {
                output = "rnnoise:Output";
                input = "compressor:Left input";
              }
              {
                output = "rnnoise:Output";
                input = "compressor:Right input";
              }
            ]
          else
            [
              {
                output = "rnnoise:Output (L)";
                input = "compressor:Left input";
              }
              {
                output = "rnnoise:Output (R)";
                input = "compressor:Right input";
              }
            ];

        micProcessingSetup =
          if cfg.micProcess.enable then
            [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "capture.props" = {
                    "node.name" = "MicRaw";
                    "node.description" = "HW Mic (Raw Input)";
                    "media.class" = "Audio/Sink";
                  } // micCaptureStreamProps;
                  "playback.props" = {
                    "node.name" = "MicProcessed";
                    "node.description" = "HW Mic (Processed)";
                    "media.class" = "Audio/Source";
                  } // micFilterPlaybackStreamProps;
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "ladspa";
                        name = "rnnoise";
                        plugin = "librnnoise_ladspa";
                        label = rnnoiseLabel;
                        control."VAD Threshold (%)" = cfg.micProcess.vadThreshold;
                      }
                      {
                        type = "ladspa";
                        plugin = "sc4_1882";
                        name = "compressor";
                        label = "sc4";
                        control = with cfg.micProcess.compressor; {
                          "Attack time (ms)" = attackTime;
                          "Release time (ms)" = releaseTime;
                          "Threshold level (dB)" = threshold;
                          "Ratio (1:n)" = ratio;
                          "Makeup gain (dB)" = makeupGain;
                        };
                      }
                    ];
                    links = compressorLinks;
                  };
                };
              }
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "HW-Mic ➜ Processing Chain";
                  "capture.props"."node.target" = cfg.input;
                  "playback.props" = {
                    "node.target" = "MicRaw";
                  } // lib.optionalAttrs inputIsMono monoStreamProps;
                };
              }
            ]
          else
            [
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "HW-Mic ➜ Passthrough";
                  "capture.props"."node.target" = cfg.input;
                  "playback.props" = {
                    "node.name" = "MicProcessed";
                    "node.description" = "Hardware Mic (Passthrough)";
                    "media.class" = "Audio/Source";
                  } // micPassthroughPlaybackStreamProps;
                };
              }
            ];

      in
      {
        "context.modules" =
          appChains
          ++ mainLoopbacks
          ++ micProcessingSetup
          ++ [
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "Virtual Mic (Source & Mixer)";
                "capture.props" = {
                  "node.name" = "VirtualMicInput";
                  "node.description" = "Virtual Mic Input (Mixer)";
                  "media.class" = "Audio/Sink";
                };
                "playback.props" = {
                  "node.name" = "VirtualMic";
                  "node.description" = "Input: Virtual Microphone";
                  "media.class" = "Audio/Source";
                };
              };
            }
            {
              name = "libpipewire-module-loopback";
              args = {
                "node.description" = "Processed Mic ➜ Virtual Mic Mixer";
                "capture.props"."node.target" = "MicProcessed";
                "playback.props"."node.target" = "VirtualMicInput";
              };
            }
            (
              if cfg.eq.enable then
                {
                  name = "libpipewire-module-filter-chain";
                  args = {
                    "capture.props" = {
                      "node.name" = "MainEQ";
                      "node.description" = "Main Mix (Pre-EQ)";
                      "media.class" = "Audio/Sink";
                      "audio.position" = "FL,FR";
                    };
                    "playback.props" = {
                      "node.target" = cfg.output;
                    };
                    "filter.graph" = {
                      nodes = [
                        {
                          type = "builtin";
                          label = "param_eq";
                          config.filename = cfg.eq.file;
                        }
                      ];
                    };
                  };
                }
              else
                {
                  name = "libpipewire-module-loopback";
                  args = {
                    "capture.props" = {
                      "node.name" = "MainEQ";
                      "node.description" = "Main Mix (Passthrough)";
                      "media.class" = "Audio/Sink";
                      "audio.position" = "FL,FR";
                    };
                    "playback.props" = {
                      "node.target" = cfg.output;
                    };
                  };
                }
            )
          ];
      };
  };
}
