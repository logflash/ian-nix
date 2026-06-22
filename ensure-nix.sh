#!/usr/bin/env bash
#
# ensure-nix.sh - Ensure the Nix package manager is installed on macOS.
#
# Idempotent and safe to run repeatedly:
#   * if Nix already works, nothing is installed and the version is reported;
#   * flakes are enabled only when not already on (no duplicate config lines);
#   * a broken or partial install is reported with recovery steps rather than
#     re-running the installer over a dirty /nix.
#
# Usage:
#   ./ensure-nix.sh
#
# Environment overrides:
#   NIX_INSTALLER_URL   Installer script URL (default: https://nixos.org/nix/install)
#   NIX_INSTALL_ARGS    Extra args passed to the installer (default: --daemon)
#   ENABLE_FLAKES       Enable nix-command + flakes in nix.conf (default: 1; set 0 to skip)
#
set -euo pipefail

NIX_INSTALLER_URL="${NIX_INSTALLER_URL:-https://nixos.org/nix/install}"
NIX_INSTALL_ARGS="${NIX_INSTALL_ARGS:---daemon}"
ENABLE_FLAKES="${ENABLE_FLAKES:-1}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Source the Nix profile scripts so `nix` is on PATH for an existing install or
# immediately after a fresh one, without opening a new terminal.
load_nix_env() {
  # Multi-user (daemon) install.
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    # shellcheck disable=SC1091
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
  # Single-user install / per-user profile.
  if [ -e "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
    # shellcheck disable=SC1091
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  fi
}

# Return success only if nix runs, not merely if it is on PATH. This catches a
# half-installed state where the binary exists but the store or daemon do not.
nix_works() {
  command -v nix >/dev/null 2>&1 && nix --version >/dev/null 2>&1
}

# Detect files from a previous (possibly broken) install. The installer refuses
# to run over a dirty /nix, so this gates a reinstall attempt.
nix_artifacts_present() {
  [ -e /nix/store ] || [ -e /nix/var/nix ] || [ -e /etc/nix/nix.conf ]
}

# Enable flakes and the unified nix command in nix.conf. Inspects the effective
# (last-wins) experimental-features line and appends only when flakes are not
# already enabled, so repeated runs do not duplicate config.
enable_flakes() {
  local conf_dir="${HOME}/.config/nix"
  local conf_file="${conf_dir}/nix.conf"

  # Check the last experimental-features line (the one Nix honors) and exit 0
  # only if it already enables both nix-command and flakes.
  if [ -f "${conf_file}" ] && awk '
      /^[[:space:]]*experimental-features[[:space:]]*=/ { last = $0 }
      END { exit (last ~ /nix-command/ && last ~ /flakes/) ? 0 : 1 }
    ' "${conf_file}"; then
    log "Flakes already enabled in ${conf_file}"
    return 0
  fi

  mkdir -p "${conf_dir}"

  # Add a trailing newline first if the file lacks one, to avoid joining lines.
  if [ -s "${conf_file}" ] && [ -n "$(tail -c1 "${conf_file}")" ]; then
    printf '\n' >> "${conf_file}"
  fi

  printf '%s\n' "experimental-features = nix-command flakes" >> "${conf_file}"
  log "Enabled flakes in ${conf_file}"
}

# Run the official installer on a clean machine, then reload the environment.
install_nix() {
  command -v curl >/dev/null 2>&1 || die "curl is required but was not found"

  log "Nix not found. Installing via the official installer..."
  log "  installer: ${NIX_INSTALLER_URL}"
  log "  args:      ${NIX_INSTALL_ARGS}"
  warn "The installer needs administrator (sudo) privileges and may prompt for a password."

  # shellcheck disable=SC2086
  sh <(curl --proto '=https' --tlsv1.2 -fsSL "${NIX_INSTALLER_URL}") ${NIX_INSTALL_ARGS}

  # Make the freshly installed Nix usable in this shell.
  load_nix_env
}

# Prompt for git author identity and store it via `git config --global` (writes
# ~/.gitconfig), keeping personal info out of this repo. Idempotent: skips if
# already set, and only prompts on an interactive terminal.
configure_git_identity() {
  command -v git >/dev/null 2>&1 || return 0
  if [ -n "$(git config --global user.name 2>/dev/null)" ] \
    && [ -n "$(git config --global user.email 2>/dev/null)" ]; then
    log "Git identity already set ($(git config --global user.name) <$(git config --global user.email)>)."
    return 0
  fi
  if [ ! -t 0 ]; then
    warn "Git identity not set; set it later with: git config --global user.name / user.email"
    return 0
  fi
  local name email
  printf 'Git author name:  '; IFS= read -r name
  printf 'Git author email: '; IFS= read -r email
  [ -n "${name}" ]  && git config --global user.name  "${name}"
  [ -n "${email}" ] && git config --global user.email "${email}"
  log "Git identity configured."
}

main() {
  # macOS only.
  if [ "$(uname -s)" != "Darwin" ]; then
    die "this script only supports macOS (detected: $(uname -s))"
  fi

  log "Detected macOS on $(uname -m)."

  load_nix_env

  if nix_works; then
    log "Nix is already installed: $(nix --version)"
  elif nix_artifacts_present; then
    # Partial or broken install: stop rather than compound it. Re-running prints
    # the same guidance and changes nothing.
    die "found existing Nix files under /nix but the 'nix' command isn't working.
This looks like a partial or broken install, and re-running the installer would
fail. Repair the install first, then run ./ensure-nix.sh again:
  - Determinate installer:  /nix/nix-installer uninstall
  - Official installer:     https://nix.dev/manual/nix/latest/installation/uninstall"
  else
    install_nix

    if nix_works; then
      log "Nix installed successfully: $(nix --version)"
    else
      warn "Nix was installed, but isn't on PATH in this shell yet."
      warn "Open a new terminal (or source the profile script below) to start using it:"
      warn "  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    fi
  fi

  if [ "${ENABLE_FLAKES}" != "0" ]; then
    enable_flakes
  fi

  configure_git_identity
}

main "$@"
