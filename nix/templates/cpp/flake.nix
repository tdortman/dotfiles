{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
      ];
      llvm = pkgs.llvmPackages_21;
      nativeBuildInputs = with pkgs; [
        gnumake
        llvm.clang-tools
        llvm.lldb
      ];
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      system = "x86_64-linux";

    in
    {
      devShells.${system}.default = pkgs.mkShell {

        inherit buildInputs nativeBuildInputs;
        CPATH = with pkgs; lib.makeIncludePath [ ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs);
      };
    };
}
