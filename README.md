# ian-nix

A reproducible macOS configuration built on [Nix](https://nixos.org): a bootstrap
script to install Nix, plus a [flake](https://nixos.wiki/wiki/Flakes) that
declares the whole machine (system settings, user environment, and Homebrew)
with [nix-darwin](https://github.com/nix-darwin/nix-darwin),
[home-manager](https://github.com/nix-community/home-manager), and
[nix-homebrew](https://github.com/zhaofengli/nix-homebrew).

## Layout

| Path                  | Purpose                                                            |
| --------------------- | ----------------------------------------------------------------- |
| `ensure-nix.sh`       | Idempotent bootstrap: install Nix and enable flakes.              |
| `configure-darwin.sh` | Apply the flake (`darwin-rebuild switch`); also `build` / `check`. |
| `flake.nix`           | Entry point: wires nix-darwin, home-manager, and Homebrew together. |
| `modules/darwin.nix`  | System-level config (macOS defaults, Nix settings, Homebrew).     |
| `modules/home.nix`    | User-level config (CLI tools, dotfiles) via home-manager.         |

## What's managed

| Area | What | Where |
| ---- | ---- | ----- |
| **Nix** | flakes + `nix-command` enabled | `modules/darwin.nix` |
| **CLI tools** (nixpkgs, pinned) | `ripgrep`, `fd`, `jq`, `awscli2`, `cloudflared`, `stripe-cli`, `temporal-cli`, `nodejs_22`, `pnpm` | `modules/home.nix` |
| **Homebrew brews** | `colima`, `docker`, `docker-compose` (container tooling) | `modules/darwin.nix` |
| **Homebrew casks** | `claude-code`, `codex`, `ngrok`, `visual-studio-code` | `modules/darwin.nix` |
| **Shell** | zsh (`.zshrc` / `.zprofile`), `starship` prompt, `atuin`, `gh` | `modules/home.nix` |
| **Git** | global identity + `push.default` | `modules/home.nix` |
| **VSCode** | `settings.json` (declarative, read-only); 9 baseline extensions seeded but UI-editable | `modules/home.nix` |

Node comes from `nodejs_22` (nixpkgs), replacing `node` and `nvm`. Per-project
flake dev shells can provide other versions.

## Quick start

```sh
# 1. Install Nix (idempotent, safe to re-run).
./ensure-nix.sh

# 2. Edit the placeholders at the top of flake.nix: username, hostname, system.
#    Defaults for this machine are pre-filled.

# 3. (Optional) preview without touching the system.
./configure-darwin.sh build

# 4. Build and activate. The first run bootstraps darwin-rebuild; later runs use
#    it directly. Re-run after editing the configuration.
./configure-darwin.sh
```

`configure-darwin.sh` stages the flake files (flakes ignore untracked files),
then runs `darwin-rebuild switch` against `darwinConfigurations.<LocalHostName>`.
Override the target with `FLAKE_HOST=…`.

After the first switch, `experimental-features` is owned declaratively by
`modules/darwin.nix`, making the `nix.conf` line written by `ensure-nix.sh`
redundant (harmless to leave). Editing `modules/darwin.nix` or `modules/home.nix`
and re-running `./configure-darwin.sh` converges the machine to match, on this
Mac or any other.

> [!NOTE]
> The script auto-stages with `git add` (it never commits). When running commands
> manually, note that flakes only see git-tracked files; `git add` after creating
> or renaming any `.nix` file.

## `ensure-nix.sh`

Ensures the Nix package manager is installed on macOS with flakes enabled.
Idempotent and safe to run repeatedly: it converges to the same state without
repeating work or duplicating config.

### Usage

```sh
./ensure-nix.sh
```

The installer requires administrator privileges and may prompt for a password
(`sudo`).

### What it does

- Verifies it is running on macOS (works on both Apple Silicon and Intel).
- Sources the Nix profile scripts, then checks whether `nix` actually **works**
  (runs it, not just a PATH lookup); if so, prints the version and installs
  nothing.
- On a clean machine, installs Nix via the official installer in `--daemon`
  (multi-user) mode, the recommended setup on macOS, and loads the new
  environment so `nix` is usable in the same shell.
- If it finds Nix files under `/nix` but `nix` is not working (a partial or
  broken install), it **stops with repair instructions** rather than re-running
  the installer over a dirty store, so a re-run never makes things worse.
- Enables `nix-command` and `flakes` in `~/.config/nix/nix.conf`, but only if
  they are not already on. It inspects the effective (last-wins)
  `experimental-features` setting, so re-running never duplicates the line.

### Configuration

Override these environment variables to customize the install:

| Variable            | Default                         | Description                                            |
| ------------------- | ------------------------------- | ------------------------------------------------------ |
| `NIX_INSTALLER_URL` | `https://nixos.org/nix/install` | Installer script URL.                                  |
| `NIX_INSTALL_ARGS`  | `--daemon`                      | Extra args passed to the installer.                    |
| `ENABLE_FLAKES`     | `1`                             | Enable nix-command + flakes in nix.conf; set `0` to skip. |

For example, to use the [Determinate Systems installer](https://install.determinate.systems)
instead:

```sh
NIX_INSTALLER_URL=https://install.determinate.systems/nix \
NIX_INSTALL_ARGS="install --no-confirm" ./ensure-nix.sh
```

### Requirements

- macOS
- `curl` (ships with macOS)
