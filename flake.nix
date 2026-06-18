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
    inputs@{ self, nixpkgs, nix-darwin, home-manager, nix-homebrew }:
    let
      # Machine-specific settings - edit for the target host.
      username = "ian";
      hostname = "Ians-MacBook-Pro";       # from `scutil --get LocalHostName`
      system   = "aarch64-darwin";         # Apple Silicon; "x86_64-darwin" on Intel
    in
    {
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs username hostname; };

        modules = [
          ./modules/darwin.nix

          # Manage (and pin) Homebrew itself, declaratively.
          nix-homebrew.darwinModules.nix-homebrew

          # Run home-manager as part of the system rebuild.
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Back up any pre-existing dotfile (e.g. ~/.zshrc) to <name>.backup on
            # the first switch instead of failing on the collision.
            home-manager.backupFileExtension = "backup";
            home-manager.users.${username} = import ./modules/home.nix;
            home-manager.extraSpecialArgs = { inherit inputs username; };
          }
        ];
      };
    };
}
