{
  python3,
  makeWrapper,
  stdenvNoCC,
  kdialog,
  lib,
}:
let
  src = ./.;
  py = python3;
  runtimeModules = [
    "daemon/policyd.py"
    "daemon/merge_policy.py"
    "daemon/session_context.py"
    "proxy/proxy.py"
    "proxy/hosts.py"
    "proxy/proc_context.py"
    "dns/dns_proxy.py"
    "dns/dns_cache.py"
    "dns/dns_wire.py"
    "cli/approve.py"
    "cli/elevate.py"
    "cli/ui_client.py"
    "graphical_env.py"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "agent-sandbox-policy";
  version = "0.1.0";
  src = src;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p $out/share/agent-sandbox-policy $out/bin
    for module in ${builtins.concatStringsSep " " runtimeModules}; do
      cp $src/$module $out/share/agent-sandbox-policy/$(basename "$module")
    done
    for script in policyd proxy merge_policy elevate approve; do
      makeWrapper ${py}/bin/python3 $out/bin/agent-sandbox-$script \
        --add-flags $out/share/agent-sandbox-policy/$script.py \
        --prefix PYTHONPATH : $out/share/agent-sandbox-policy
    done
    makeWrapper ${py}/bin/python3 $out/bin/agent-sandbox-ui \
      --add-flags $out/share/agent-sandbox-policy/ui_client.py \
      --prefix PYTHONPATH : $out/share/agent-sandbox-policy \
      --prefix PATH : ${lib.makeBinPath [ kdialog ]} \
      --set-default AGENT_SANDBOX_KDIALOG ${kdialog}/bin/kdialog
    makeWrapper ${py}/bin/python3 $out/bin/agent-sandbox-dns-proxy \
      --add-flags $out/share/agent-sandbox-policy/dns_proxy.py \
      --prefix PYTHONPATH : $out/share/agent-sandbox-policy
  '';
}
