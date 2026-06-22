# VSCode. The app comes from the visual-studio-code Homebrew cask
# (darwin/homebrew.nix). programs.vscode is intentionally unused, as it would
# install a second, Nix-built VSCode; only settings and a baseline extension set
# are managed here.
{ pkgs, lib, ... }:
{
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
}
