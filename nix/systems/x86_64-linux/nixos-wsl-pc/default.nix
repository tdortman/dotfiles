{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./services.nix
  ];

  environment = {
    systemPackages = with pkgs; [
      wsl2-ssh-agent
    ];

    variables = {
      CPATH = [
        "${pkgs.libglvnd.dev}/include"
      ];

      JAVA_HOME = "${pkgs.jdk}";

      LD_LIBRARY_PATH = [
        "${pkgs.stdenv.cc.cc.lib}/lib"
        "${pkgs.llvmPackages_21.libcxx}/lib"
        "${pkgs.llvmPackages_21.libunwind}/lib"
      ];

      LIBGL_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";
      LIBVA_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";

      PKG_CONFIG_PATH = [
        "${pkgs.openssl.dev}/lib/pkgconfig"
      ];

      VK_DRIVER_FILES = "${pkgs.mesa}/share/vulkan/icd.d/dzn_icd.x86_64.json";
      VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/dzn_icd.x86_64.json";
      VK_LAYER_PATH = "${pkgs.mesa}/share/vulkan/explicit_layer.d";
    };
  };

  networking.hostName = "nixos-wsl-pc";
  nvidia.cuda.enable = true;
  system.stateVersion = "24.11";

  users.users.${config.common.username} = {
    extraGroups = [
      "networkmanager"
      "podman"
      "render"
      "video"
      "wheel"
    ];

    isNormalUser = true;
  };

  virtualisation.podman.enable = false;

  wsl = {
    enable = true;
    defaultUser = config.common.username;
    wslConf.interop.appendWindowsPath = false;
  };
}
