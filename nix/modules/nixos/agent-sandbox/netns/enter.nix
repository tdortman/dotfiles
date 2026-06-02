{ stdenv, libcap }:
stdenv.mkDerivation {
  pname = "agent-sandbox-enter";
  version = "0.1.0";
  dontUnpack = true;
  buildInputs = [ libcap ];
  buildPhase = "$CC -O2 -o agent-sandbox-enter ${./enter.c} -lcap";
  installPhase = "install -Dm755 agent-sandbox-enter $out/bin/agent-sandbox-enter";
}
