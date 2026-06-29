# Shell + interactive CLI tools (home-manager modules install + wire integration).
{ ... }:
{
  programs.atuin = {
    enable = true;
    settings = {
      # Default filter mode on search startup.
      filter_mode = "directory";

      # Ctrl+/ cycles the filter mode (global -> host -> session -> directory)
      # in every keymap mode. Ctrl+R also cycles.
      keymap =
        let
          cycle = {
            "ctrl-/" = "cycle-filter-mode";
          };
        in
        {
          emacs = cycle;
          vim_insert = cycle;
          vim_normal = cycle;
        };
    };
  };

  programs.gh.enable = true;
  programs.zoxide.enable = true;        # smarter cd
  programs.eza.enable = true;           # modern ls (aliased below)
  programs.bat.enable = true;           # modern cat
  programs.lazygit.enable = true;       # git TUI
  programs.fzf.enable = true;           # fuzzy finder (Ctrl+T / Alt+C)

  # direnv + nix-direnv: per-project environments load automatically on cd.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Starship prompt. home-manager generates starship.toml and wires zsh.
  programs.starship = {
    enable = true;
    settings = {
      package.disabled = true;
      python.disabled = true;
      git_status.disabled = true;
      nodejs.disabled = true;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold green)";
      };
    };
  };

  # zsh. home-manager generates ~/.zshrc and ~/.zprofile. Starship and atuin
  # integration are added automatically.
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls = "eza --git";
      ll = "eza -lah --git";
      tree = "eza --tree";
      grep = "rg";
      find = "fd";
    };

    # Custom .zshrc additions.
    initContent = ''
      zle_highlight=(default:fg=yellow)

      # nvm: node is managed by nvm (per-project via .nvmrc), NOT nixpkgs — the
      # nixpkgs node build crashes Next 16's TypeScript worker. See packages.nix.
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

      # Auto-switch to the project's pinned node on cd when an .nvmrc is found
      # (walks up the tree, so it works from any subdir of the repo).
      autoload -U add-zsh-hook
      load-nvmrc() {
        if [ -n "$(nvm_find_nvmrc)" ]; then
          nvm use --silent
        fi
      }
      add-zsh-hook chpwd load-nvmrc
      load-nvmrc
    '';

    # Put Homebrew binaries on PATH for interactive shells.
    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };
}
