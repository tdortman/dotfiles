{ inputs, ... }:

final: _: {
  # unstable = import inputs.nixpkgs-unstable {
  #   system = final.stdenv.hostPlatform.system;
  #   config.allowUnfree = true;
  # };

  cuda = import inputs.nixpkgs-flox {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };

    system = final.stdenv.hostPlatform.system;
  };

  master = import inputs.nixpkgs-master {
    config.allowUnfree = true;
    system = final.stdenv.hostPlatform.system;
  };
}
