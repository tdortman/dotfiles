{
  pkgs,
  config,
  ...
}:

{
  imports = [
    ./services.nix
  ];

  nvidia.cuda.enable = true;

  networking.hostName = "nixos-wsl-pc";

  environment.systemPackages = with pkgs; [
    wsl2-ssh-agent
  ];

  environment.variables = {
    LIBVA_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";
    VK_DRIVER_FILES = "${pkgs.mesa}/share/vulkan/icd.d/dzn_icd.x86_64.json";
    VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/dzn_icd.x86_64.json";
    VK_LAYER_PATH = "${pkgs.mesa}/share/vulkan/explicit_layer.d";
    LIBGL_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";

    JAVA_HOME = "${pkgs.jdk}";

    LD_LIBRARY_PATH = [
      "${pkgs.stdenv.cc.cc.lib}/lib"
      "${pkgs.llvmPackages_21.libcxx}/lib"
      "${pkgs.llvmPackages_21.libunwind}/lib"
    ];

    CPATH = [
      "${pkgs.libglvnd.dev}/include"
    ];

    PKG_CONFIG_PATH = [
      "${pkgs.openssl.dev}/lib/pkgconfig"
    ];
  };

  virtualisation.podman.enable = false;

  users.users.${config.common.username} = {
    isNormalUser = true;
    extraGroups = [
      "podman"
      "wheel"
      "networkmanager"
      "video"
      "render"
    ];
  };

  wsl = {
    enable = true;
    defaultUser = config.common.username;
    wslConf.interop.appendWindowsPath = false;
  };

  system.stateVersion = "24.11";
}
