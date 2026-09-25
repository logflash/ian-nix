{
  description = "Reproducible macOS configuration (nix-darwin, home-manager, Homebrew)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Installs and pins Homebrew itself under Nix's control.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs =
    inputs@{ nix-darwin, ... }:
    let
      # User and architectures for these profiles. Macs keep their own names.
      username = "ian";
      appleSilicon = "aarch64-darwin";
      intel = "x86_64-darwin";
      mkDarwin = system: extraModules: nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs username; };
        modules = [ ./darwin ] ++ extraModules;
      };
    in
    {
      # These keys select a role and CPU, never a Mac's LocalHostName.
      darwinConfigurations = {
        default = mkDarwin appleSilicon [ ];
        intel = mkDarwin intel [ ];
        homelab = mkDarwin appleSilicon [ ./homelab/darwin.nix ];
      };
    };
}
