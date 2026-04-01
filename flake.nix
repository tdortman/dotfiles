{

  description = "There are many NixOS configs, but this one is mine";

  outputs =
    inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      snowfall.root = ./nix;
      snowfall.namespace = "custom";

      channels-config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "olm-3.2.16"
        ];
      };

      systems.modules.nixos = with inputs; [
        { _module.args.currentUsername = "tim"; }
        agenix.nixosModules.default
        nix-index-database.nixosModules.nix-index
        nix-flatpak.nixosModules.nix-flatpak
        disko.nixosModules.disko
        spicetify-nix.nixosModules.default
        home-manager.nixosModules.home-manager
      ];

      systems.hosts = {
        nixos-wsl-pc.modules = with inputs; [
          nixos-wsl.nixosModules.default
        ];
      };

      homes.modules = with inputs; [
        plasma-manager.homeModules.plasma-manager
      ];

      templates = {
        cuda.description = "CUDA development environment";
        cpp.description = "C++ development environment using llvm";
        basic.description = "Basic development environment";
        shell.description = "Shell environment";
        package.description = "Package development environment";
      };

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixfmt;
      };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-flox.url = "github:flox/nixpkgs/unstable";
    nixpkgs-temp.url = "github:NixOS/nixpkgs/pull/503185/head";

    snowfall-lib = {
      url = "github:anntnzrb/snowfall-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix/2e2234c2932a3aff5f845cda33cb1972a9e889aa";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
  };

}
