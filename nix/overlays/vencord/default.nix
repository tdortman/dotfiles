{ ... }:

final: prev: {
  # vencord = prev.vencord.overrideAttrs (oldAttrs: {
  #   version = "1.14.5";
  #   src = prev.fetchFromGitHub {
  #     owner = "Vendicated";
  #     repo = "Vencord";
  #     rev = "v${final.vencord.version}";
  #     sha256 = "sha256-FZ00lhPr4R0Bo8zwBfc/Y8eMfbTcRxjH3YwDBm1NSQk=";
  #   };
  # });
}
