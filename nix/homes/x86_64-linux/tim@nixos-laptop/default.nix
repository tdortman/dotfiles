{
  lib,
  pkgs,
  osConfig,
  ...
}:

{
  home.stateVersion = "26.11";
  onepassword.enable = true;

  programs = {
    konsole = {
      enable = true;
      defaultProfile = "default";

      profiles.default.font = {
        size = 14;
        name = "ComicCodeLigatures Nerd Font Mono";
      };
    };

    plasma = {
      enable = true;

      configFile = {
        baloofilerc."Basic Settings".Indexing-Enabled = false;

        kcminputrc."Libinput/1267/12635/ELAN072D:00 04F3:315B Touchpad" = {
          NaturalScroll = true;
          ScrollFactor = 0.75;
        };

        kded5rc.Module-browserintegrationreminder.autoload = false;
        kded6rc.PlasmaBrowserIntegration.shownCount = 1;

        kdeglobals = {
          General = {
            XftAntialias = true;
            XftHintStyle = "hintslight";
            XftSubPixel = "rgb";
          };

          General.AccentColor = "#926ee4";
          General.TerminalApplication = "ghostty";
          General.TerminalService = "com.mitchellh.ghostty.desktop";
          Sounds.Enable = false;
        };

        kwinrc = {
          # Disable overview when moving to top left corner
          Effect-overview.BorderActivate = 9;
          # For some reason the workspace setting does not persist this setting
          # so we write it directly into the config file (disable middle click paste)
          Wayland.EnablePrimarySelection = false;
          Xwayland.Scale = 1.25;
        };

        kwinrulesrc = {

          "9f92402d-ab4d-45b7-9660-516c5f837c7b" = {
            Description = "GitButler maximize";
            maximizehoriz = true;
            maximizehorizrule = 2;
            maximizevert = true;
            maximizevertrule = 2;
            types = 1;
            wmclass = "gitbutler-tauri";
            wmclasscomplete = false;
            wmclassmatch = 1;
          };

          General = {
            count = 1;
            rules = "9f92402d-ab4d-45b7-9660-516c5f837c7b";
          };
        };

        plasmanotifyrc.Notifications.PopupTimeout = 15000;

        # Some laptop power buttons emit PowerDown rather than PowerOff.
        # plasma-manager exposes PowerButtonAction, but not this Plasma 6 key.
        powerdevilrc = {
          "AC/SuspendAndShutdown".PowerDownAction = 2;
          "Battery/SuspendAndShutdown".PowerDownAction = 2;
          "LowBattery/SuspendAndShutdown".PowerDownAction = 2;
        };
      };

      fonts =
        let
          uiFont = size: {
            family = "Inter";
            pointSize = size;
          };
        in
        {
          fixedWidth = {
            family = "ComicCodeLigatures Nerd Font Mono";
            pointSize = 11;
          };

          general = uiFont 11;
          menu = uiFont 11;
          small = uiFont 9;
          toolbar = uiFont 11;
          windowTitle = uiFont 11;
        };

      kscreenlocker = {
        appearance.showMediaControls = false;
        autoLock = false;
        lockOnResume = false;
      };

      kwin = {
        cornerBarrier = false;
        edgeBarrier = 0;
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
      };

      overrideConfig = true;

      panels = [
        {
          floating = true;
          height = 48;
          hiding = "none";
          location = "bottom";
          screen = "all";

          widgets = [
            { kickoff = { }; }
            { pager = { }; }
            {
              iconTasks.launchers = [
                "applications:org.kde.kdeconnect.app.desktop"
                "applications:thunderbird.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:librewolf.desktop"
                "applications:discord.desktop"
                "applications:spotify.desktop"
              ];
            }
            "org.kde.plasma.marginsseparator"
            {
              systemTray.items = {
                # Seems to not be functional at the moment, in fact the volume
                # applet doesn't seem to exist at all?
                #
                # https://github.com/nix-community/plasma-manager/issues/565
                configs."org.kde.plasma.volume".config.General.showVirtualDevices = true;
              };
            }
            {
              digitalClock = {
                calendar.firstDayOfWeek = "monday";

                date = {
                  enable = true;
                  format.custom = "dd/MM/yyyy";
                  position = "belowTime";
                };

                time.format = "24h";

                timeZone = {
                  lastSelected = "Local";

                  selected = [
                    "America/Los_Angeles"
                    "Local"
                    "Asia/Tokyo"
                  ];
                };
              };
            }
            "org.kde.plasma.showdesktop"
          ];

        }
      ];

      powerdevil = {
        AC = {
          autoSuspend.action = "nothing";
          dimDisplay.enable = false;
          inhibitLidActionWhenExternalMonitorConnected = false;
          powerButtonAction = "hibernate";
          turnOffDisplay.idleTimeout = "never";
          whenLaptopLidClosed = "hibernate";
          whenSleepingEnter = "standbyThenHibernate";
        };

        battery = {
          autoSuspend = {
            action = "hibernate";
            idleTimeout = 600;
          };

          dimDisplay.enable = false;
          inhibitLidActionWhenExternalMonitorConnected = false;
          powerButtonAction = "hibernate";
          turnOffDisplay.idleTimeout = "never";
          whenLaptopLidClosed = "hibernate";
          whenSleepingEnter = "standbyThenHibernate";
        };

        lowBattery = {
          autoSuspend = {
            action = "hibernate";
            idleTimeout = 600;
          };

          dimDisplay = {
            enable = true;
            idleTimeout = 60;
          };

          inhibitLidActionWhenExternalMonitorConnected = false;
          powerButtonAction = "hibernate";
          turnOffDisplay.idleTimeout = 300;
          whenLaptopLidClosed = "hibernate";
          whenSleepingEnter = "standbyThenHibernate";
        };
      };

      session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";

      shortcuts = {
        "services/com.mitchellh.ghostty.desktop".new-window = "Meta+Return";
        "services/net.local.hdr-toggle.desktop"._launch = lib.mkIf osConfig.hdr.enable "Meta+Alt+B";
        "services/systemsettings.desktop"._launch = "Meta+I";
      };

      startup.startupScript.teams = {
        runAlways = true;

        text = ''
          setsid teams-for-linux --wayland --minimized --enableIncomingCallToast &
        '';
      };

      windows.allowWindowsToRememberPositions = true;

      workspace = {
        enableMiddleClickPaste = false;
        lookAndFeel = "org.kde.breezedark.desktop";
        theme = "breeze-dark";
        tooltipDelay = 5;
        wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/MilkyWay/contents/images/5120x2880.png";
      };
    };
  };

  services.wl-clip-persist = {
    clipboardType = "regular";
    enable = true;
  };
}
