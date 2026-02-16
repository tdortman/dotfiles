{
  pkgs,
  osConfig,
  lib,
  ...
}:

{
  home.stateVersion = "25.11";

  onepassword.enable = true;

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
        inter = size: {
          family = "Inter";
          pointSize = size;
        };
      in
      {
        small = inter 8;
        general = inter 10;
        toolbar = inter 10;
        menu = inter 10;
        windowTitle = inter 10;

        fixedWidth = {
          family = "ComicCodeLigatures Nerd Font Mono";
          pointSize = 10;
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
      plasmashellrc."PlasmaViews/Panel 278/Defaults".thickness = 48;
      plasmashellrc."PlasmaViews/Panel 25/Defaults".thickness = 48;
      plasmashellrc."PlasmaViews/Panel 662/Defaults".thickness = 48;

      kdeglobals.Sounds.Enable = false;
      kdeglobals.General.TerminalApplication = "ghostty";
      kdeglobals.General.TerminalService = "com.mitchellh.ghostty.desktop";

      kdeglobals.General.AccentColor = "#926ee4";
      baloofilerc."Basic Settings".Indexing-Enabled = false;

      plasmanotifyrc.Notifications.PopupTimeout = 15000;

      "plasma-org.kde.plasma.desktop-appletsrc" = {
        "Containments/278/Applets/296/Configuration/Appearance" = {
          fontWeight = 400;
          selectedTimeZones = "America/Los_Angeles,Local,Asia/Tokyo";
        };
        "Containments/662/Applets/681/Configuration/Appearance" = {
          fontWeight = 400;
          selectedTimeZones = "America/Los_Angeles,Local,Asia/Tokyo";
        };
      };

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

      kwinrulesrc."28f2a5bd-b708-4cde-b12e-cc2e3bc1def1" = {
        desktopfile = "/run/current-system/sw/share/applications/StreamController.desktop";
        desktopfilerule = 4;
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
