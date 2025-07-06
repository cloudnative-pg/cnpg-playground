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

        # Setup 'kc' as a 'kubectl cnpg' alias
        source <(kubectl cnpg completion bash)
        alias kc="kubectl cnpg"
        complete -o default -F __start_kubectl-cnpg kc
      '';

      packages = [
        pkgs.kubectl
        pkgs.kubernetes-helm
        pkgs.kind
        pkgs.jq
        pkgs.curl
        pkgs.kubectl-cnpg
        pkgs.kubectl-view-secret
        pkgs.cmctl
        pkgs.k9s
        pkgs.lazydocker
        pkgs.btop
     ];
    };
  });
}
