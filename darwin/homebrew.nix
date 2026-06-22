# Homebrew packages. GUI apps as casks; CLI tools come from nixpkgs (home/).
# The Homebrew module writes a Brewfile and runs `brew bundle` on each switch.
{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # "none": brew bundle installs what's listed but NEVER uninstalls anything
      # else. ("zap" once removed claude-code@latest because the declared token
      # didn't match the installed one, deleting the `claude` binary.)
      # Prune undeclared packages deliberately with `brew bundle cleanup`.
      cleanup = "none";
    };
    taps  = [ ];
    brews = [
      # Container tooling, kept in Homebrew for macOS/colima integration. These
      # also exist in nixpkgs and can move to home/ to pin them.
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
      # "Magnet" = 441258766;   # Mac App Store apps (requires the `mas` brew)
    };
  };
}
