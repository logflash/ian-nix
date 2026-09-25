#!/usr/bin/env bash
#
# configure-darwin.sh - Apply the nix-darwin configuration in this repository.
#
# Wraps `darwin-rebuild switch` against the flake in this directory so the system
# and home-manager environment converge to match the configuration. Idempotent:
# re-running with no changes activates the same generation and does nothing new.
#
#   ./configure-darwin.sh           # build + activate (default action: switch)
#   ./configure-darwin.sh build     # build only: no sudo, no activation
#   ./configure-darwin.sh check     # nix flake check: validate the flake evaluates
#
# On the first run (before darwin-rebuild exists) switch bootstraps via
# `nix run nix-darwin`. Run this wrapper as your regular user; it uses sudo
# for system activation.
#
# Environment overrides:
#   FLAKE_DIR    Directory containing flake.nix (default: this script's directory)
#   FLAKE_CONFIG darwinConfigurations name to build (default: Apple Silicon or Intel shared profile)
#   NO_GIT_ADD   Set to 1 to skip auto-staging files for the flake.
#
set -euo pipefail

# Ensure nix-command + flakes are available even if nix.conf has not enabled them
# yet. The extra- prefix appends, so existing features are not clobbered.
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${FLAKE_DIR:-$SCRIPT_DIR}"
if [ -z "${FLAKE_CONFIG:-}" ]; then
  case "$(uname -m)" in
    arm64) FLAKE_CONFIG=default ;;
    x86_64) FLAKE_CONFIG=intel ;;
    *) FLAKE_CONFIG=default ;;
  esac
fi
NO_GIT_ADD="${NO_GIT_ADD:-0}"
ACTION="${1:-switch}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Source the Nix profile scripts so nix and darwin-rebuild are on PATH even in a
# non-login shell (mirrors ensure-nix.sh).
load_nix_env() {
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    # shellcheck disable=SC1091
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
  if [ -e "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
    # shellcheck disable=SC1091
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  fi
}

nix_works() { command -v nix >/dev/null 2>&1 && nix --version >/dev/null 2>&1; }

# Flakes evaluate only git-tracked files. Stage new or modified files under the
# flake dir so the build sees them. Staging only; this never commits.
stage_flake_files() {
  git -C "${FLAKE_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [ -n "$(git -C "${FLAKE_DIR}" status --porcelain)" ] || return 0
  if [ "${NO_GIT_ADD}" = "1" ]; then
    warn "Uncommitted changes present and NO_GIT_ADD=1 - the flake will ignore untracked files."
    return 0
  fi
  log "Staging changes so the flake can see them (git add -A; not committing)."
  git -C "${FLAKE_DIR}" add -A
}

# nix-darwin aborts the first activation if installer-owned files already
# exist in /etc. Move them only after the system builds, and restore them if
# activation fails before nix-darwin replaces them.
backed_up_etc_files=()
etc_backup_paths=()
backup_conflicting_etc_files() {
  local f backup n
  for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
    [ -L "$f" ] && continue          # already a nix-darwin symlink
    [ -f "$f" ] || continue          # nothing to back up
    backup="$f.before-nix-darwin"
    n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="$f.before-nix-darwin.$n"
      n=$((n + 1))
    done
    log "Backing up $f -> $backup so nix-darwin can manage it."
    sudo mv "$f" "$backup"
    backed_up_etc_files+=("$f")
    etc_backup_paths+=("$backup")
  done
}

restore_conflicting_etc_files() {
  local i f backup
  for ((i=${#backed_up_etc_files[@]}-1; i>=0; i--)); do
    f="${backed_up_etc_files[$i]}"
    backup="${etc_backup_paths[$i]}"
    if [ ! -e "$f" ] && [ ! -L "$f" ]; then
      warn "Restoring $f after failed activation."
      sudo mv "$backup" "$f" || warn "Could not restore $f; saved copy is $backup"
    else
      warn "$f now exists; saved copy is $backup"
    fi
  done
}

main() {
  [ "$(uname -s)" = "Darwin" ] || die "this script only supports macOS (detected: $(uname -s))"
  [ -f "${FLAKE_DIR}/flake.nix" ] || die "no flake.nix found in ${FLAKE_DIR}"
  [ "$(id -u)" -ne 0 ] || die "run this script as your regular user: ./configure-darwin.sh ${ACTION} (it uses sudo for activation)"
  FLAKE_DIR="$(cd -- "$FLAKE_DIR" && pwd)"

  load_nix_env
  nix_works || die "Nix is not available; run ./ensure-nix.sh first, then re-run this."

  stage_flake_files

  # Use one immutable source for both the user build and root activation.
  # This also lets activation read the flake without access to Downloads.
  local flake_source target system_attr
  flake_source="$(FLAKE_DIR="$FLAKE_DIR" nix eval --impure --raw --expr '(builtins.getFlake (builtins.getEnv "FLAKE_DIR")).outPath')"
  target="path:${flake_source}#${FLAKE_CONFIG}"
  system_attr="path:${flake_source}#darwinConfigurations.${FLAKE_CONFIG}.system"

  case "${ACTION}" in
    check)
      log "Validating flake: ${FLAKE_DIR}"
      nix flake check "path:${flake_source}"
      ;;
    build)
      log "Building (no activation): darwinConfigurations.${FLAKE_CONFIG}.system"
      nix build --no-link "$system_attr"
      log "Build OK - nothing was activated."
      ;;
    switch)
      log "Building: darwinConfigurations.${FLAKE_CONFIG}.system"
      nix build --no-link "$system_attr"
      warn "Activation needs administrator rights and may prompt for a password."
      sudo -v
      trap restore_conflicting_etc_files EXIT
      backup_conflicting_etc_files
      if command -v darwin-rebuild >/dev/null 2>&1; then
        log "Applying: darwin-rebuild switch --flake ${target}"
        sudo -H env NIX_CONFIG="$NIX_CONFIG" "$(command -v darwin-rebuild)" switch --flake "$target"
      else
        log "First run - darwin-rebuild not installed yet; bootstrapping via 'nix run nix-darwin'..."
        sudo -H env NIX_CONFIG="$NIX_CONFIG" "$(command -v nix)" run nix-darwin/master#darwin-rebuild -- switch --flake "$target"
      fi
      trap - EXIT
      log "Done. Open a new shell (or run 'exec zsh') to pick up the new environment."
      ;;
    *)
      die "unknown action '${ACTION}' (use: switch | build | check)"
      ;;
  esac
}

main "$@"
