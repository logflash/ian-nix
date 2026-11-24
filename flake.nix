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
      # Supplied by configure-darwin.sh so personal account names stay local.
      username =
        let value = builtins.getEnv "DARWIN_USERNAME";
        in if value != "" then value else throw "Set DARWIN_USERNAME or use configure-darwin.sh";
      namespace =
        let value = builtins.getEnv "DARWIN_CONFIG_NAMESPACE";
        in if value != "" then value else throw "Set DARWIN_CONFIG_NAMESPACE or use configure-darwin.sh";
      appleSilicon = "aarch64-darwin";
      intel = "x86_64-darwin";
      mkDarwin = system: extraModules: nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs username namespace; };
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
