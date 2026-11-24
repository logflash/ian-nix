# macOS Nix configuration

A reproducible macOS configuration built on [Nix](https://nixos.org): a bootstrap
script to install Nix, plus a [flake](https://nixos.wiki/wiki/Flakes) that
declares the whole machine (system settings, user environment, and Homebrew)
with [nix-darwin](https://github.com/nix-darwin/nix-darwin),
[home-manager](https://github.com/nix-community/home-manager), and
[nix-homebrew](https://github.com/zhaofengli/nix-homebrew).

## Layout

| Path                  | Purpose                                                            |
| --------------------- | ----------------------------------------------------------------- |
| `ensure-nix.sh`       | Idempotent bootstrap: install Nix, enable flakes, set git identity. |
| `configure-darwin.sh` | Apply the flake (`darwin-rebuild switch`); also `build` / `check`. |
| `configure-homelab.sh` | Apply the shared Mac setup plus UTM, the Ubuntu VM, and Cloudflare Tunnel on an Apple Silicon homelab Mac. |
| `flake.nix`           | Entry point: shared Apple Silicon and Intel profiles, plus the homelab profile. |
| `darwin/`             | System (nix-darwin) modules — `default.nix`, `homebrew.nix`.       |
| `homelab/`            | UTM and Cloudflare Tunnel setup, VM resources and installer pin, and UTM AppleScript provisioning. |
| `home/`               | User (home-manager) modules — `default.nix`, `packages.nix`, `shell.nix`, `git.nix`, `mouse.nix`, `vscode.nix`. |

## What's managed

| Area | What | Where |
| ---- | ---- | ----- |
| **Nix** | flakes + `nix-command` enabled | `darwin/default.nix` |
| **CLI tools** (nixpkgs, pinned) | `ripgrep`, `fd`, `jq`, `btop`, `dust`, `tldr`, `awscli2`, `cloudflared`, `ngrok`, `stripe-cli`, `temporal-cli`, `uv`, `nodejs_24`, `pnpm_10`, `python3` | `home/packages.nix` |
| **Homebrew brews** | `colima`, `docker`, `docker-compose` (container tooling) | `darwin/homebrew.nix` |
| **Homebrew casks** | `claude-code`, `codex`, `linearmouse`, `slack`, `visual-studio-code` | `darwin/homebrew.nix` |
| **Mouse** | Natural scrolling and pointer acceleration off; LinearMouse starts at login and scrolls three lines per wheel tick without acceleration | `darwin/default.nix`, `home/mouse.nix` |
| **Shell** | zsh, `starship`, `atuin`, `zoxide`, `fzf`, `eza`, `bat`, `direnv`, `lazygit`, `gh` | `home/shell.nix` |
| **Git** | `push.default`, `merge.conflictstyle`, delta pager (identity set by `ensure-nix.sh`) | `home/git.nix` |
| **VSCode** | `settings.json` (read-only); baseline extensions seeded but UI-editable | `home/vscode.nix` |

The shell uses nvm for Node version selection; see `home/shell.nix`.
On first launch, grant LinearMouse access in **System Settings → Privacy &
Security → Accessibility** when macOS asks. Scroll acceleration cannot be
changed by the app until that permission is enabled. The macOS natural-scrolling
default also affects trackpads; LinearMouse's fixed-step rule applies only to
mice.

## Quick start

```sh
# 1. Install Nix (idempotent, safe to re-run).
./ensure-nix.sh

# 2. The wrapper selects your current macOS account and CPU architecture.

# 3. (Optional) preview without touching the system.
./configure-darwin.sh build

# 4. Build and activate. The first run bootstraps darwin-rebuild; later runs use
#    it directly. Re-run after editing the configuration.
./configure-darwin.sh
```

`configure-darwin.sh` stages the flake files (flakes ignore untracked files),
then runs `darwin-rebuild switch` against the shared profile for the Mac's CPU
(`default` on Apple Silicon, `intel` on Intel). The homelab profile adds to the
same shared modules; it does not replace them.
The wrapper uses your current macOS username and the checkout directory name
for local service and config paths. Keep the checkout directory name stable
after activating the homelab profile.
The configuration leaves macOS's LocalHostName and ComputerName alone. Override
the flake configuration key with `FLAKE_CONFIG=…` if needed.

Run both scripts as your regular user, with `./` and without `sudo`. They ask
for administrator access when installation or activation needs it. The command
is `./configure-darwin.sh`; there is no `darwin-configure.sh` in this repo.
The switch builds the system before moving installer-owned `/etc` files, and
restores them if activation fails before nix-darwin replaces them.
It uses the same immutable flake snapshot for the build and activation.

After the first switch, `experimental-features` is owned declaratively by
`darwin/default.nix`, making the `nix.conf` line written by `ensure-nix.sh`
redundant (harmless to leave). Editing files under `darwin/` or `home/` and
re-running `./configure-darwin.sh` converges the machine to match, on this Mac or
any other.

## Homelab Mac

Run this on the Apple Silicon homelab Mac as your regular user, without `sudo`:

```sh
./configure-homelab.sh build   # optional: build the homelab profile only
./configure-homelab.sh         # activate shared Darwin + homelab additions, then create VM
./configure-homelab.sh vm      # VM step only, useful after an interrupted activation
./configure-homelab.sh finish  # after Ubuntu installation, remove installer drive
./configure-homelab.sh tunnel      # set up the first route, or check and skip if configured
./configure-homelab.sh tunnel-add  # explicitly add another hostname/service route
```

The script calls `configure-darwin.sh` with `FLAKE_CONFIG=homelab`, so it starts
with all shared Mac settings. Only this profile installs the UTM Homebrew cask.
After activation, the script downloads the Ubuntu Server 24.04.5 ARM64 ISO from
Ubuntu, verifies its pinned SHA-256, and uses UTM's AppleScript API to create
`ubuntu-server-24.04` with 8 GiB RAM, 4 vCPUs, a 128 GiB virtual disk, shared
networking, and a display. The verified ISO is moved into the VM's `.utm/Data`
directory before first boot. UTM owns the mutable VM data in its library.
Re-running the script checks the existing VM's resources and does not replace
its disk. Open UTM and start the VM to finish the Ubuntu installer using your
macOS account name. SSH keys are intentionally left for later. After installation, stop the
VM and run `./configure-homelab.sh finish` to remove the installer drive before
booting the installed system. The installer download is about 3.6 GiB and needs
several GiB of free space.

`configure-darwin.sh` alone remains the shared setup for other Macs. The flake
does not set `LocalHostName` or assign the homelab role from the hostname; the
script you run chooses the role. `configure-homelab.sh check` and `build` only
validate or build the homelab Darwin profile; they do not download the ISO or
create a VM. The `vm` action checks or creates the VM without rerunning Darwin
activation; it requires UTM to be installed already.

The first interactive `./configure-homelab.sh` run also offers to set up a
locally managed Cloudflare Tunnel on the Mac. It prompts for a tunnel name, a
public hostname, and a local service URL such as `http://localhost:3000`.
Press Enter at the hostname prompt to defer setup. Cloudflare must already
manage DNS for the hostname's domain. The script opens Cloudflare login in your
browser, creates or reuses the named tunnel, validates its ingress rules, and
adds the DNS route. It never overwrites an existing DNS record. A published
hostname is publicly reachable unless you protect it with a Cloudflare Access
policy. If you already created a CNAME to this tunnel, setup keeps it; an A,
AAAA, or CNAME pointing elsewhere blocks setup so an existing site is not
redirected. For a separate dashboard, use a name such as `dash.example.com`.

The homelab Nix profile installs `cloudflared` as a launchd system service
running as your user, so the connector keeps running after logout. The service
starts automatically after reboot and waits for first-time setup to create its
config. Tunnel credentials stay under
`~/.cloudflared/`; the prompted routes and credential-file path stay in
`~/.config/<repo-directory>/cloudflared.json`. Neither is placed in the Nix store or Git.
Later runs of `./configure-homelab.sh` and `./configure-homelab.sh tunnel`
validate and skip an already configured tunnel without prompting or creating another one.
Run `./configure-homelab.sh tunnel-add` to add another hostname; an existing
identical route is also skipped. Run `./configure-homelab.sh build` or `check` to validate
Nix without launching the interactive tunnel setup.

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
