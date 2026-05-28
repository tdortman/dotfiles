{ pkgs, config, ... }:

{
  environment.systemPackages =
    with pkgs;
    [
      # Editors / Shell
      neovim
      zsh
      oh-my-posh
      lazygit
      delta
      hex

      # Languages / Runtimes
      python3
      nodejs
      bun
      uv
      pixi
      volta

      # Nix tooling
      nixfmt
      nixd
      nil
      nix-output-monitor
      nix-init
      cachix
      hydra-check
      age
      devenv

      # Dev tools
      git
      git-filter-repo
      git-lfs
      gh
      direnv
      atuin
      fzf
      zoxide
      jq
      file
      pkg-config
      mold-unwrapped
      openssl
      bear
      gdb
      valgrind
      hyperfine
      oha
      shfmt
      ruff

      # System / CLI utilities
      curl
      wget
      moor
      stow
      unzip
      zip
      unrar
      p7zip-rar
      trashy
      rm-improved
      dust
      eza
      bat
      ripgrep
      fd
      sd
      fastfetch
      tokei
      kmod
      lz4
      openssh
      docker
      containerd
      qemu
      chezmoi

      # Media / Graphics
      ffmpeg-full
      imagemagick
      gifsicle
      vulkan-tools
      vulkan-loader
      libva-utils
      vdpauinfo
      mesa-demos
      mesa
      clinfo
      opencl-headers
      libgcc

      # GTK / Qt theming
      gtk4
      gtk3
      gtk2
      kdePackages.breeze-gtk

      # Databases
      sqlite
      sqlitebrowser
      turso-cli

      # Misc
      codesnap
      shellcheck
      zenity
      rclone
      atool
      ookla-speedtest

      # Documentation
      man-pages
      man-pages-posix
    ]
    ++ [ (if config.nvidia.driver.enable then pkgs.btop-cuda else pkgs.btop) ];
}
