{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      llvm = pkgs.llvmPackages_21;
      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
      ];

      nativeBuildInputs = with pkgs; [
        gnumake
        llvm.clang-tools
        llvm.lldb
      ];

    in
    {
      devShells.${system}.default = pkgs.mkShell {

        inherit buildInputs nativeBuildInputs;
        CPATH = with pkgs; lib.makeIncludePath [ ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs);
      };
    };
}
