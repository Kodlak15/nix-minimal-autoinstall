{
  description = "My NixOS autoinstall script";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      configuration = {
        default = ./configuration.nix;
      };
    in {
      packages.default =
        pkgs.writeShellScriptBin "autoinstall.sh"
        (builtins.readFile ./autoinstall.sh);
    });
}
