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
    awscli2
    cloudflared
    stripe-cli
    temporal-cli
    nodejs_22
    pnpm
    uv
  ];

  # Programs with home-manager modules that also manage their configuration.
  programs.atuin.enable = true;
  programs.gh.enable = true;

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

  # Global git configuration.
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Ian Henriques";
        email = "ian@generaltranslation.com";
      };
      push.default = "current";
    };
  };

  # zsh. home-manager generates ~/.zshrc and ~/.zprofile. Starship and atuin
  # integration are added automatically.
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

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
