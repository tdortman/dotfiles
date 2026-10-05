{
  lib,
  pkgs,
  inputs,
  osConfig,
  system,
  ...
}:

{
  custom = {
    auto-minimize-covered.enable = true;

    panelLaunchers = [
      "applications:org.kde.kdeconnect.app.desktop"
      "applications:thunderbird.desktop"
      "applications:com.mitchellh.ghostty.desktop"
      "applications:so.stencil.tern.desktop"
      "applications:org.kde.dolphin.desktop"
      "applications:librewolf.desktop"
      "applications:discord.desktop"
      "applications:steam.desktop"
      "applications:spotify.desktop"
    ];
  };

  home = {
    file.".cargo/config.toml".text = ''
      [target.'cfg(target_os = "linux")']
      linker = "${pkgs.clang}/bin/clang"
      rustflags = ["-C", "link-arg=-fuse-ld=${pkgs.mold}/bin/mold"]
    '';

    stateVersion = "25.11";
  };

  programs = {
    plasma = {
      configFile = {
        kcminputrc."Libinput/1133/16531/Logitech PRO X" = {
          PointerAcceleration = 0.500;
          PointerAccelerationProfile = 1;
          ScrollFactor = 2;
        };

        kwinrulesrc = {
          "28f2a5bd-b708-4cde-b12e-cc2e3bc1def1" = {
            desktopfile = "/run/current-system/sw/share/applications/StreamController.desktop";
            desktopfilerule = 4;
          };

          # Tern ignores its own saved size, so pin the launch geometry.
          "2c49b7ea-aa4c-480f-b254-0caf6115a221" = {
            size = "1364,1234";
            Description = "Tern size and maximize";
            maximizehoriz = true;
            maximizehorizrule = 3; # Apply initially
            maximizevert = true;
            maximizevertrule = 3; # Apply initially
            sizerule = 3; # Apply initially; 2 (Force) blocks resize/maximize
            types = 1;
            wmclass = "so.stencil.tern";
            wmclasscomplete = false;
            wmclassmatch = 1;
          };

          General = {
            count = 2;
            rules = "9f92402d-ab4d-45b7-9660-516c5f837c7b,2c49b7ea-aa4c-480f-b254-0caf6115a221";
          };
        };

      };

      shortcuts."services/net.local.hdr-toggle.desktop"._launch =
        lib.mkIf osConfig.custom.hdr.enable "Meta+Alt+B";

      startup.startupScript = {
        discord = {
          runAlways = true;

          text = ''
            setsid discord --enable-blink-features=MiddleClickAutoscroll &
          '';
        };

        display-layout = {
          runAlways = true;

          text = "${osConfig.system.build.displayLayout}/bin/display-layout ${
            osConfig.custom."display-layout".loginLayout
          }";
        };

        spotify = {
          runAlways = true;

          text = ''
            setsid spotify --enable-blink-features=MiddleClickAutoscroll &
          '';
        };

        # nheko = {
        #   text = ''
        #     setsid nheko &
        #   '';
        #   runAlways = true;
        # };
        steam = {
          runAlways = true;

          text = ''
            setsid steam -silent &
          '';
        };

        teams = {
          runAlways = true;

          text = ''
            setsid teams-for-linux --wayland --minimized --enableIncomingCallToast &
          '';
        };
      };

    };

    voxtype = {
      enable = true;
      package = inputs.voxtype.packages.${system}.vulkan;
      engine = "whisper";
      model.name = "large-v3-turbo";
      service.enable = true;

      settings = {
        output = {
          append_text = " ";
          fallback_to_clipboard = true;
          mode = "paste";
          paste_keys = "ctrl+shift+v";
          shift_enter_newlines = true;
        };

        audio.max_duration_secs = 600;
        hotkey.enabled = false;
        osd.enabled = false;

        parakeet = {
          model = "parakeet-tdt-0.6b-v3";
          model_type = "tdt";
          on_demand_loading = true;
          streaming = false;
        };

        text = {
          replacements."HTTP too" = "HTTP/2";
          spoken_punctuation = true;
        };

        whisper = {
          gpu_isolation = true;

          language = [
            "en"
            "de"
          ];

          on_demand_loading = true;
        };
      };
    };
  };

  systemd.user.services.voxtype.Service.Environment = lib.mkAfter [
    # For the `onnx-cuda` package: its ONNX Runtime loads CUDA at runtime
    # "LD_LIBRARY_PATH=${
    #   lib.makeLibraryPath (
    #     with pkgs.cudaPackages;
    #     [
    #       cuda_cudart
    #       cuda_nvrtc
    #       cudnn
    #       libcublas
    #     ]
    #   )
    # }"
    # "LD_PRELOAD=${pkgs.cudaPackages.cuda_nvrtc.lib}/lib/libnvrtc.so"

    "DOTOOL_XKB_LAYOUT=de"
    "DOTOOL_XKB_VARIANT="
    "XKB_DEFAULT_LAYOUT=de"
    "XKB_DEFAULT_VARIANT="
    "XKB_DEFAULT_OPTIONS="
  ];

  xdg = {
    # Brio 100 does 1920x1080@30 MJPEG but Teams' getUserMedia asks 720p.
    # Force 1080p capture
    configFile."teams-for-linux/config.json".text = builtins.toJSON {
      media.camera.resolution = {
        enabled = true;
        height = 1080;
        mode = "override";
        width = 1920;
      };
    };

  };
}
