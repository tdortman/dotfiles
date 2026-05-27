{
  lib,
  pkgs,
  system,
  osConfig,
  inputs,
  ...
}:

{
  home.stateVersion = "25.11";

  onepassword.enable = true;

  services.wl-clip-persist = {
    enable = true;
    clipboardType = "regular";
  };

  programs.voxtype = {
    enable = true;
    engine = "whisper";
    package = inputs.voxtype.packages.${system}.vulkan;
    service.enable = true;

    model.name = "large-v3-turbo";

    settings = {
      hotkey.enabled = false;
    };
  };

  programs.plasma = {
    enable = true;
    overrideConfig = true;

    workspace = {
      theme = "breeze-dark";
      lookAndFeel = "org.kde.breezedark.desktop";
      wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/MilkyWay/contents/images/5120x2880.png";

      enableMiddleClickPaste = false;

      tooltipDelay = 5;
    };

    panels = [
      {
        location = "bottom";
        height = 48;
        floating = true;
        screen = "all";
        hiding = "none";

        widgets = [
          { kickoff = { }; }
          { pager = { }; }
          {
            iconTasks = {
              launchers = [
                "applications:org.kde.kdeconnect.app.desktop"
                "applications:thunderbird.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:librewolf.desktop"
                "applications:discord.desktop"
                "applications:steam.desktop"
                "applications:spotify.desktop"
              ];
            };
          }
          "org.kde.plasma.marginsseparator"
          {
            systemTray = {
              items = {
                # Seems to not be functional at the moment, in fact the volume
                # applet doesn't seem to exist at all?
                #
                # https://github.com/nix-community/plasma-manager/issues/565
                configs."org.kde.plasma.volume".config.General.showVirtualDevices = true;
              };
            };
          }
          {
            digitalClock = {
              date = {
                enable = true;
                format.custom = "dd/MM/yyyy";
                position = "belowTime";
              };
              time.format = "24h";
              timeZone = {
                selected = [
                  "America/Los_Angeles"
                  "Local"
                  "Asia/Tokyo"
                ];
                lastSelected = "Local";
              };
              calendar.firstDayOfWeek = "monday";
            };
          }
          "org.kde.plasma.showdesktop"
        ];

      }
    ];

    kscreenlocker = {
      autoLock = false;
      appearance.showMediaControls = false;
    };

    kwin = {
      effects.shakeCursor.enable = false;

      titlebarButtons = {
        left = [
          "more-window-actions"
          "keep-above-windows"
          "keep-below-windows"
        ];

        right = [
          "help"
          "minimize"
          "maximize"
          "close"
        ];
      };

      edgeBarrier = 0;
      cornerBarrier = false;
    };

    fonts =
      let
        uiFont = size: {
          family = "Inter";
          pointSize = size;
        };
      in
      {
        small = uiFont 9;
        general = uiFont 11;
        toolbar = uiFont 11;
        menu = uiFont 11;
        windowTitle = uiFont 11;

        fixedWidth = {
          family = "ComicCodeLigatures Nerd Font Mono";
          pointSize = 11;
        };
      };

    windows.allowWindowsToRememberPositions = true;

    shortcuts = {
      "services/systemsettings.desktop" = {
        _launch = "Meta+I";
      };
      "services/com.mitchellh.ghostty.desktop" = {
        new-window = "Meta+Return";
      };
      "services/net.local.hdr-toggle.desktop"."_launch" = lib.mkIf osConfig.hdr.enable "Meta+Alt+B";
    };

    powerdevil.AC = {
      powerButtonAction = "hibernate";
      autoSuspend.action = "nothing";
      whenSleepingEnter = "standbyThenHibernate";
      turnOffDisplay.idleTimeout = "never";
      dimDisplay.enable = false;
    };

    session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";

    configFile = {
      kdeglobals.Sounds.Enable = false;
      kdeglobals.General.TerminalApplication = "ghostty";
      kdeglobals.General.TerminalService = "com.mitchellh.ghostty.desktop";

      kdeglobals.General.AccentColor = "#926ee4";
      baloofilerc."Basic Settings".Indexing-Enabled = false;

      plasmanotifyrc.Notifications.PopupTimeout = 15000;

      kcminputrc."Libinput/1133/16531/Logitech PRO X" = {
        PointerAccelerationProfile = 1;
        PointerAcceleration = 0.500;
        ScrollFactor = 1;
      };

      kdeglobals.General = {
        XftAntialias = true;
        XftHintStyle = "hintslight";
        XftSubPixel = "rgb";
      };

      kwinrc = {
        # For some reason the workspace setting does not persist this setting
        # so we write it directly into the config file (disable middle click paste)
        Wayland.EnablePrimarySelection = false;

        # Disable overview when moving to top left corner
        "Effect-overview".BorderActivate = 9;
      };

      kded5rc.Module-browserintegrationreminder.autoload = false;
      kded6rc.PlasmaBrowserIntegration.shownCount = 1;

      kwinrulesrc = {
        "28f2a5bd-b708-4cde-b12e-cc2e3bc1def1" = {
          desktopfile = "/run/current-system/sw/share/applications/StreamController.desktop";
          desktopfilerule = 4;
        };

        General = {
          rules = "9f92402d-ab4d-45b7-9660-516c5f837c7b";
          count = 1;
        };

        "9f92402d-ab4d-45b7-9660-516c5f837c7b" = {
          Description = "GitButler maximize";
          types = 1;
          wmclass = "gitbutler-tauri";
          wmclasscomplete = false;
          wmclassmatch = 1;

          maximizehoriz = true;
          maximizehorizrule = 2;
          maximizevert = true;
          maximizevertrule = 2;
        };
      };
    };

    startup.startupScript = {
      discord = {
        text = ''
          setsid discord --enable-blink-features=MiddleClickAutoscroll &
        '';
        runAlways = true;
      };

      spotify = {
        text = ''
          setsid spotify --enable-blink-features=MiddleClickAutoscroll &
        '';
        runAlways = true;
      };

      nheko = {
        text = ''
          setsid nheko &
        '';
        runAlways = true;
      };

      steam = {
        text = ''
          setsid steam -silent &
        '';
        runAlways = true;
      };

      teams = {
        text = ''
          setsid teams-for-linux --wayland --minimized --enableIncomingCallToast &
        '';
        runAlways = true;
      };
    };
  };

  programs.konsole = {
    enable = true;
    defaultProfile = "default";

    profiles.default = {
      font = {
        name = "ComicCodeLigatures Nerd Font Mono";
        size = 14;
      };
    };
  };
}
