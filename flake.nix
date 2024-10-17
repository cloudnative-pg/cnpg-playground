{
  description = "CNPG Training - Dev Shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
    pkgs = import nixpkgs {inherit system; };
      in {
    devShells.default = pkgs.mkShell {
      shellHook = ''
        # Setup 'k' as a 'kubectl' alias
        source <(kubectl completion bash)

        alias k=kubectl
        complete -o default -F __start_kubectl k
      '';

      packages = [
        pkgs.kubectl
        pkgs.helm
        pkgs.kind
        pkgs.jq
        pkgs.curl
        pkgs.kubectl-cnpg
     ];
    };
  });
}
