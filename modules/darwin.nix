# System-level configuration, applied by `darwin-rebuild switch`.
{ pkgs, username, hostname, ... }:
{
  ## Identity ##################################################################
  system.primaryUser = username;          # required by recent nix-darwin for user defaults

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  networking.hostName = hostname;
  networking.computerName = hostname;

  ## Nix itself ###############################################################
  # Declarative replacement for the nix.conf edit made by ensure-nix.sh. After
  # the first switch this is the source of truth for these settings.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # With the Determinate Systems installer, Determinate manages the daemon; set
  # nix.enable = false here to avoid a conflict. The default (official) installer
  # used by ensure-nix.sh needs no change.

  ## Packages #################################################################
  # System packages are kept minimal; per-user tools live in home.nix.
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  programs.zsh.enable = true;             # enable the system zsh integration for Nix

  ## Homebrew #################################################################
  # nix-homebrew installs and pins Homebrew under Nix's control.
  nix-homebrew = {
    enable = true;
    user = username;
    autoMigrate = true;                   # adopt an existing Homebrew install if present
    # enableRosetta = true;               # also manage x86_64 casks on Apple Silicon
  };

  # The Homebrew module writes a Brewfile and runs `brew bundle` on each switch.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # "none": brew bundle installs what's listed but NEVER uninstalls anything
      # else. "zap" once removed claude-code@latest (the declared token didn't
      # match the installed one), which deleted the `claude` binary. Never again.
      # To prune undeclared packages deliberately, run `brew bundle cleanup`.
      cleanup = "none";
    };
    taps  = [ ];
    brews = [
      # Container tooling, kept in Homebrew for macOS/colima integration. These
      # also exist in nixpkgs and can move to home.nix to pin them.
      "colima"
      "docker"
      "docker-compose"
    ];
    casks = [
      "claude-code@latest"   # must match the installed cask token exactly, or zap removes it
      "codex"
      "linearmouse"
      "ngrok"
      "slack"
      "visual-studio-code"
    ];
    masApps = {
      # "Magnet" = 441258766;             # Mac App Store apps (requires the `mas` brew)
    };
  };

  ## State version ############################################################
  # Set once; bump only after reading the nix-darwin changelog.
  system.stateVersion = 5;
}
