# User-level configuration, managed by home-manager.
{ pkgs, lib, username, ... }:
{
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Keep ~/.local/bin on PATH.
  home.sessionPath = [ "$HOME/.local/bin" ];

  # CLI tools, pinned by the flake.
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    btop
    dust
    tldr
    awscli2
    cloudflared
    stripe-cli
    temporal-cli
    uv

    # Project toolchain
    nodejs_24        # engines.node ^24.13.1 (nixpkgs provides 24.15.0)
    pnpm_10          # packageManager pnpm@10.x (nixpkgs provides 10.34.0)
    python3          # node-gyp for native modules (node-pty, sharp, ...)
    # bun            # optional: sync:repos + alternate server runtime
  ];

  # Programs with home-manager modules that also manage their configuration.
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

  # Modern CLI tools with home-manager modules (install + zsh integration).
  programs.zoxide.enable = true;        # smarter cd
  programs.eza.enable = true;           # modern ls (aliased below)
  programs.bat.enable = true;           # modern cat
  programs.lazygit.enable = true;       # git TUI

  # fzf fuzzy finder. Its zsh integration also binds Ctrl+R, which atuin uses;
  # if fzf ends up grabbing it, disable fzf's keybinding. Ctrl+T / Alt+C are
  # unaffected.
  programs.fzf.enable = true;

  # direnv + nix-direnv: per-project environments (e.g. a flake dev shell for a
  # different Node version) load automatically on cd.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Starship prompt. home-manager generates starship.toml and wires the zsh
  # integration.
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

  # Global git configuration. Identity (user.name/email) is set separately via
  # `git config --global` (by ensure-nix.sh) so it stays out of this repo; git
  # merges it with the settings below.
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
    '';

    # Put Homebrew binaries on PATH for interactive shells.
    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };

  ## VSCode ###################################################################
  # The VSCode app is provided by the visual-studio-code Homebrew cask
  # (darwin.nix). programs.vscode is intentionally unused, as it would install a
  # second, Nix-built VSCode; only settings and a baseline extension set are
  # managed here.

  # User settings. Written as a read-only symlink, so changes made through the
  # Settings UI do not persist; edit here instead. Remove this block to keep
  # settings.json UI-editable.
  home.file."Library/Application Support/Code/User/settings.json".source =
    (pkgs.formats.json { }).generate "vscode-settings.json" {
      "claudeCode.preferredLocation" = "panel";
      "gitlens.ai.model" = "vscode";
      "gitlens.ai.vscode.model" = "copilotcli:claude-haiku-4.5";
      "git.blame.editorDecoration.enabled" = true;
    };

  # Baseline extensions, installed with the cask's code CLI so they live in the
  # standard, UI-editable extensions directory; extensions added from the
  # Marketplace persist. Idempotent: only missing extensions are installed.
  home.activation.installVSCodeExtensions =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      code_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
      if [ -x "$code_bin" ]; then
        installed="$("$code_bin" --list-extensions 2>/dev/null || true)"
        for ext in \
          anthropic.claude-code \
          eamodio.gitlens \
          manishsencha.readme-preview \
          ms-python.debugpy \
          ms-python.python \
          ms-python.vscode-pylance \
          ms-python.vscode-python-envs \
          oxc.oxc-vscode \
          xyc.vscode-mdx-preview; do
          if ! printf '%s\n' "$installed" | grep -qix "$ext"; then
            $DRY_RUN_CMD "$code_bin" --install-extension "$ext" || true
          fi
        done
      else
        echo "home-manager: VSCode app not found; skipping extension seed (re-run after the cask installs)."
      fi
    '';

  # State version compatibility marker. Set once; do not change without
  # consulting the home-manager changelog.
  home.stateVersion = "24.11";
}
