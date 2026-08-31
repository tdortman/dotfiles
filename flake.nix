{

  description = "There are many NixOS configs, but this one is mine";

  outputs =
    inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;

      snowfall = {
        namespace = "custom";
        root = ./nix;
      };

      src = ./.;

      channels-config = {
        allowUnfree = true;

        permittedInsecurePackages = [
          "electron-40.10.5" # winboat
          "olm-3.2.16" # nheko
        ];
      };

      homes.modules = with inputs; [
        plasma-manager.homeModules.plasma-manager
        voxtype.homeManagerModules.default
      ];

      supportedSystems = [
        "x86_64-linux"
      ];

      systems = {
        hosts.nixos-wsl-pc.modules = with inputs; [
          nixos-wsl.nixosModules.default
        ];

        modules.nixos = with inputs; [
          agenix.nixosModules.default
          agent-sandbox.nixosModules.agent-sandbox
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          nix-flatpak.nixosModules.nix-flatpak
          nix-index-database.nixosModules.nix-index
          spicetify-nix.nixosModules.default
        ];
      };

      templates = {
        basic.description = "Basic development environment";
        cpp.description = "C++ development environment using llvm";
        cuda.description = "CUDA development environment";
        cuda-oxide.description = "Rust development environment for cuda-oxide projects";
        package.description = "Package development environment";
        rust.description = "Rust development environment using rust-overlay";
        rust-shell.description = "Rust shell using rust-overlay";
        shell.description = "Shell environment";
      };

      outputs-builder =
        channels:
        let
          pkgs = channels.nixpkgs;
          treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
            imports = [ inputs.pedantix.treefmtModules.default ];

            programs.pedantix = {
              enable = true;

              settings = {
                attrs = {
                  blank-lines = 1;
                  blank-lines-mode = "multiline";
                  flatten = true;
                  merge = true;
                  name-style = "identifier";
                };

                formatter = "nixfmt";
                inherit-placement = "front";
                inherits.name-style = "identifier";
                lets.name-style = "identifier";
                lists.sort = false;
              };
            };

            projectRootFile = "flake.nix";
          };
        in
        {
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
              program = "${script}/bin/update-packages";
              type = "app";
            };

          checks.formatting = treefmt.config.build.check inputs.self;
          formatter = treefmt.config.build.wrapper;
        };
    };

  inputs = {
    agenix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ryantm/agenix";
    };

    agent-sandbox.url = "github:tdortman/agent-sandbox";

    codex-desktop-linux = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ilysenko/codex-desktop-linux";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };

    flake-utils-plus.url = "github:Dines97/flake-utils-plus";

    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    nix-index-database = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/nix-index-database";
    };

    nixos-wsl = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/NixOS-WSL/main";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-flox.url = "github:flox/nixpkgs/unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-temp.url = "github:NixOS/nixpkgs/pull/540416/head";

    pedantix = {
      inputs = {
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
      };

      url = "github:swarsel/pedantix";
    };

    plasma-manager = {
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:nix-community/plasma-manager";
    };

    snowfall-lib = {
      inputs = {
        flake-utils-plus.follows = "flake-utils-plus";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:anntnzrb/snowfall-lib";
    };

    spicetify-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:tdortman/spicetify-nix";
    };

    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };

    voxtype = {
      inputs.nixpkgs.follows = "nixpkgs-flox";
      url = "github:peteonrails/voxtype";
    };
  };
}
