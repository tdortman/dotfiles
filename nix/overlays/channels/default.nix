{ inputs, ... }:

final: prev: {
  # unstable = import inputs.nixpkgs-unstable {
  #   system = final.stdenv.hostPlatform.system;
  #   config.allowUnfree = true;
  # };

  temp = import inputs.nixpkgs-temp {
    system = final.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  cuda = import inputs.nixpkgs-flox {
    system = final.stdenv.hostPlatform.system;
    config.allowUnfree = true;
    config.cudaSupport = true;
  };

  master = import inputs.nixpkgs-master {
    system = final.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
}
