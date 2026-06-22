# System configuration (nix-darwin), applied by `darwin-rebuild switch`.
{ pkgs, inputs, username, hostname, ... }:
{
  imports = [
    ./homebrew.nix
    inputs.home-manager.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  ## Identity ##################################################################
  system.primaryUser = username;          # required by recent nix-darwin for user defaults

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  networking.hostName = hostname;
  networking.computerName = hostname;

  ## Nix ######################################################################
  # Declarative replacement for the nix.conf edit made by ensure-nix.sh. After
  # the first switch this is the source of truth for these settings.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # With the Determinate Systems installer, Determinate manages the daemon; set
  # nix.enable = false here to avoid a conflict. The default (official) installer
  # used by ensure-nix.sh needs no change.

  ## System packages (minimal; per-user tools live in home/) ##################
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  programs.zsh.enable = true;             # enable the system zsh integration for Nix

  ## home-manager #############################################################
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # Back up any pre-existing dotfile (e.g. ~/.zshrc) to <name>.backup on the
    # first switch instead of failing on the collision.
    backupFileExtension = "backup";
    extraSpecialArgs = { inherit inputs username; };
    users.${username}.imports = [ ../home ];
  };

  ## Homebrew (the package list lives in homebrew.nix) ########################
  # nix-homebrew installs and pins Homebrew under Nix's control.
  nix-homebrew = {
    enable = true;
    user = username;
    autoMigrate = true;                   # adopt an existing Homebrew install if present
    # enableRosetta = true;               # also manage x86_64 casks on Apple Silicon
  };

  ## State version (set once; read the nix-darwin changelog before changing) ###
  system.stateVersion = 5;
}
