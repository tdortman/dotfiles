{
  lib,
  pkgs,
  osConfig,
  ...
}:

{
  home.stateVersion = "26.11";

  onepassword.enable = true;

  services.wl-clip-persist = {
    enable = true;
    clipboardType = "regular";
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
      lockOnResume = false;
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

    powerdevil.battery = {
      powerButtonAction = "hibernate";
      whenLaptopLidClosed = "hibernate";
      inhibitLidActionWhenExternalMonitorConnected = false;
      autoSuspend.idleTimeout = 600;
      autoSuspend.action = "hibernate";
      dimDisplay.enable = false;
      whenSleepingEnter = "standbyThenHibernate";
      turnOffDisplay.idleTimeout = "never";
    };

    powerdevil.lowBattery = {
      powerButtonAction = "hibernate";
      whenLaptopLidClosed = "hibernate";
      inhibitLidActionWhenExternalMonitorConnected = false;
      autoSuspend.idleTimeout = 600;
      autoSuspend.action = "hibernate";
      whenSleepingEnter = "standbyThenHibernate";
      turnOffDisplay.idleTimeout = 300;
      dimDisplay = {
        enable = true;
        idleTimeout = 60;
      };
    };

    powerdevil.AC = {
      powerButtonAction = "hibernate";
      whenLaptopLidClosed = "hibernate";
      inhibitLidActionWhenExternalMonitorConnected = false;
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

      kdeglobals.General = {
        XftAntialias = true;
        XftHintStyle = "hintslight";
        XftSubPixel = "rgb";
      };

      kcminputrc."Libinput/1267/12635/ELAN072D:00 04F3:315B Touchpad" = {
        NaturalScroll = true;
        ScrollFactor = 0.75;
      };

      kwinrc = {
        # For some reason the workspace setting does not persist this setting
        # so we write it directly into the config file (disable middle click paste)
        Wayland.EnablePrimarySelection = false;

        # Disable overview when moving to top left corner
        "Effect-overview".BorderActivate = 9;

        Xwayland.Scale = 1.25;
      };

      kded5rc.Module-browserintegrationreminder.autoload = false;
      kded6rc.PlasmaBrowserIntegration.shownCount = 1;

      # Some laptop power buttons emit PowerDown rather than PowerOff.
      # plasma-manager exposes PowerButtonAction, but not this Plasma 6 key.
      powerdevilrc = {
        "AC/SuspendAndShutdown".PowerDownAction = 2;
        "Battery/SuspendAndShutdown".PowerDownAction = 2;
        "LowBattery/SuspendAndShutdown".PowerDownAction = 2;
      };

      kwinrulesrc = {

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
