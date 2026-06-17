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

      overlays = with inputs; [
        llm-agents.overlays.default
      ];

      systems.modules.nixos = with inputs; [
        agenix.nixosModules.default
        nix-index-database.nixosModules.nix-index
        nix-flatpak.nixosModules.nix-flatpak
        disko.nixosModules.disko
        spicetify-nix.nixosModules.default
        home-manager.nixosModules.home-manager
        agent-sandbox.nixosModules.agent-sandbox
      ];

      # Snowfall auto-imports nix/modules/nixos/* and invokes each module while
      # collecting imports; currentUsername must be in specialArgs for that path.
      systems.hosts = {
        nixos-pc.specialArgs.currentUsername = "tim";
        nixos-vm.specialArgs.currentUsername = "tim";
        nixos-wsl-pc = {
          specialArgs.currentUsername = "tim";
          modules = with inputs; [
            nixos-wsl.nixosModules.default
          ];
        };
      };

      homes.modules = with inputs; [
        plasma-manager.homeModules.plasma-manager
        voxtype.homeManagerModules.default
        agent-sandbox.homeModules.agent-sandbox
      ];

      templates = {
        cuda.description = "CUDA development environment";
        cpp.description = "C++ development environment using llvm";
        basic.description = "Basic development environment";
        shell.description = "Shell environment";
        package.description = "Package development environment";
        rust.description = "Rust development environment using rust-overlay";
        rust-shell.description = "Rust shell using rust-overlay";
        cuda-oxide.description = "Rust development environment for cuda-oxide projects";
      };

      outputs-builder =
        channels:
        let
          pkgs = channels.nixpkgs;
        in
        {
          formatter = pkgs.nixfmt;

          apps.update =
            let
              script = pkgs.writeShellScriptBin "update-packages" ''
                set -euo pipefail
                repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
                exit_code=0

                for updater in "$repo_root"/nix/packages/*/update.sh; do
                  if [[ -f "$updater" ]]; then
                    name=$(basename "$(dirname "$updater")")
                    echo "==> Updating $name..."
                    if ! (cd "$repo_root" && "$updater"); then
                      echo "    FAILED: $name"
                      exit_code=1
                    fi
                  fi
                done

                exit $exit_code
              '';
            in
            {
              type = "app";
              program = "${script}/bin/update-packages";
            };
        };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-flox.url = "github:flox/nixpkgs/unstable";
    nixpkgs-temp.url = "github:NixOS/nixpkgs/pull/524195/head";
    nixpkgs-librewolf.url = "github:NixOS/nixpkgs/9eac87a12312b8f60dd52e1c6e1a265f6fc7f5fc";

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
      url = "github:tdortman/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    voxtype = {
      url = "github:peteonrails/voxtype";
      inputs.nixpkgs.follows = "nixpkgs-flox";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    llm-agents.url = "github:numtide/llm-agents.nix";

    agent-sandbox = {
      url = "github:tdortman/agent-sandbox";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.snowfall-lib.follows = "snowfall-lib";
    };
  };
}
