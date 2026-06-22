# User configuration (home-manager). Aggregates the per-concern modules below.
{ username, ... }:
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./git.nix
    ./vscode.nix
  ];

  home = {
    username = username;
    homeDirectory = "/Users/${username}";

    # Keep ~/.local/bin on PATH.
    sessionPath = [ "$HOME/.local/bin" ];

    # State version compatibility marker. Set once; do not change without
    # consulting the home-manager changelog.
    stateVersion = "24.11";
  };
}
