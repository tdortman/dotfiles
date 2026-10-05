{
  config,
  lib,
  ...
}:

{
  options.custom.auto-minimize-covered.enable = lib.mkEnableOption "minimizing fully covered Discord and Spotify windows";

  config = lib.mkIf config.custom.auto-minimize-covered.enable {
    programs.plasma.configFile.kwinrc.Plugins.auto-minimize-coveredEnabled = true;

    xdg.dataFile = {
      "kwin/scripts/auto-minimize-covered/contents/code/main.js".source = ./auto-minimize-covered.js;

      "kwin/scripts/auto-minimize-covered/metadata.json".text = builtins.toJSON {
        KPackageStructure = "KWin/Script";

        KPlugin = {
          Description = "Minimize selected apps when a maximized window covers them";
          Id = "auto-minimize-covered";
          License = "MIT";
          Name = "Auto-minimize covered apps";
          Version = "1.0";
        };

        X-Plasma-API = "javascript";
        X-Plasma-MainScript = "code/main.js";
      };
    };
  };
}
