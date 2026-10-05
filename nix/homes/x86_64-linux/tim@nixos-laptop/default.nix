{
  lib,
  osConfig,
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
      "applications:spotify.desktop"
    ];
  };

  home.stateVersion = "26.11";

  programs.plasma = {
    configFile = {
      kcminputrc."Libinput/1267/12635/ELAN072D:00 04F3:315B Touchpad" = {
        NaturalScroll = true;
        ScrollFactor = 0.75;
      };

      kwinrc.Xwayland.Scale = 1.25;

      kwinrulesrc = {
        "2c49b7ea-aa4c-480f-b254-0caf6115a221" = {
          Description = "Tern maximize";
          maximizehoriz = true;
          maximizehorizrule = 3; # Apply initially
          maximizevert = true;
          maximizevertrule = 3; # Apply initially
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

      # Some laptop power buttons emit PowerDown rather than PowerOff.
      # plasma-manager exposes PowerButtonAction, but not this Plasma 6 key.
      powerdevilrc = {
        "AC/SuspendAndShutdown".PowerDownAction = 2;
        "Battery/SuspendAndShutdown".PowerDownAction = 2;
        "LowBattery/SuspendAndShutdown".PowerDownAction = 2;
      };
    };

    kscreenlocker.lockOnResume = false;

    powerdevil = {
      AC = {
        inhibitLidActionWhenExternalMonitorConnected = false;
        whenLaptopLidClosed = "hibernate";
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

    shortcuts = {
      "services/net.local.ghostty-maximized.desktop"._launch = [ ];
      "services/net.local.hdr-toggle.desktop"._launch = lib.mkIf osConfig.custom.hdr.enable "Meta+Alt+B";
    };

    startup.startupScript.teams = {
      runAlways = true;

      text = ''
        setsid teams-for-linux --wayland --minimized --enableIncomingCallToast &
      '';
    };

  };

}
