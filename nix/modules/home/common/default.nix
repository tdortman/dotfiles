{
  config,
  lib,
  ...
}:

{
  options.custom.panelLaunchers = lib.mkOption {
    type = lib.types.listOf lib.types.str;

    default = [
      "applications:org.kde.kdeconnect.app.desktop"
      "applications:com.mitchellh.ghostty.desktop"
      "applications:org.kde.dolphin.desktop"
      "applications:librewolf.desktop"
      "applications:discord.desktop"
      "applications:spotify.desktop"
    ];

    description = "Application launchers in the shared Plasma panel, in display order.";
  };

  config = {
    custom = {
      onepassword.enable = true;
      tern.enable = true;
    };

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
          kded5rc.Module-browserintegrationreminder.autoload = false;
          kded6rc.PlasmaBrowserIntegration.shownCount = 1;

          kdeglobals = {
            General = {
              AccentColor = "#926ee4";
              XftAntialias = true;
              XftHintStyle = "hintslight";
              XftSubPixel = "rgb";

            };

            Sounds.Enable = false;
          };

          kwinrc = {
            # Disable overview when moving to the top-left corner.
            Effect-overview.BorderActivate = 9;
            # The workspace setting does not persist this KWin setting.
            Wayland.EnablePrimarySelection = false;
          };

          kwinrulesrc."9f92402d-ab4d-45b7-9660-516c5f837c7b" = {
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

          plasmanotifyrc.Notifications = {
            PopupPosition = "BottomRight";
            PopupTimeout = 15000;
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
              { iconTasks.launchers = config.custom.panelLaunchers; }
              "org.kde.plasma.marginsseparator"
              "org.kde.plasma.systemtray"
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

        powerdevil.AC = {
          autoSuspend.action = "nothing";
          dimDisplay.enable = false;
          powerButtonAction = "hibernate";
          turnOffDisplay.idleTimeout = "never";
          whenSleepingEnter = "standbyThenHibernate";
        };

        # Keep panel geometry available when displays reconnect after resume.
        resetFilesExclude = [ "plasmashellrc" ];
        session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";

        shortcuts = {
          "services/com.mitchellh.ghostty.desktop".new-window = [ ];
          "services/systemsettings.desktop"._launch = "Meta+I";
        };

        startup.desktopScript.virtual-audio-devices = {
          # Configure applets after plasma-manager recreates the panels.
          priority = config.programs.plasma.startup.desktopScript.panels.priority + 1;
          # Nested applets have no scripting object to reload their configuration.
          restartServices = [ "plasma-plasmashell" ];

          text = ''
            for (const containment of panels().concat(desktops())) {
              for (const widget of containment.widgets()) {
                if (widget.type === "org.kde.plasma.volume") {
                  widget.currentConfigGroup = ["General"];
                  widget.writeConfig("showVirtualDevices", true);
                } else if (widget.type === "org.kde.plasma.systemtray") {
                  widget.currentConfigGroup = ["Applets"];
                  // Qt exposes a live list that changes with currentConfigGroup.
                  const appletIds = Array.from(widget.configGroups);
                  for (const id of appletIds) {
                    widget.currentConfigGroup = ["Applets", id];
                    if (widget.readConfig("plugin", "") === "org.kde.plasma.volume") {
                      widget.currentConfigGroup = ["Applets", id, "Configuration", "General"];
                      widget.writeConfig("showVirtualDevices", true);
                    }
                  }
                }
              }
            }
          '';
        };

        windows.allowWindowsToRememberPositions = true;

        workspace = {
          enableMiddleClickPaste = false;
          lookAndFeel = "org.kde.breezedark.desktop";
          theme = "breeze-dark";
          tooltipDelay = 5;
        };
      };
    };

    services.wl-clip-persist = {
      clipboardType = "regular";
      enable = lib.mkDefault true;
    };
  };
}
