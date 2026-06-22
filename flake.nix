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
      # Machine-specific settings - edit for the target host.
      username = "ian";
      hostname = "Ians-MacBook-Pro";       # from `scutil --get LocalHostName`
      system   = "aarch64-darwin";         # Apple Silicon; "x86_64-darwin" on Intel
    in
    {
      # Apply with: darwin-rebuild switch --flake .#${hostname}
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs username hostname; };
        modules = [ ./darwin ];
      };
    };
}
