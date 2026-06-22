# Git + delta.
{ ... }:
{
  # Identity (user.name/email) is set separately via `git config --global` (by
  # ensure-nix.sh) so it stays out of this repo; git merges it with the settings
  # below.
  programs.git = {
    enable = true;
    settings = {
      push.default = "current";
      merge.conflictstyle = "zdiff3";
    };
  };

  # delta: git pager + diff highlighting (top-level module in current home-manager).
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.navigate = true;
  };
}
