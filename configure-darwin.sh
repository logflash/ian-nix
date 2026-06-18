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
# `nix run nix-darwin`.
#
# Environment overrides:
#   FLAKE_DIR    Directory containing flake.nix (default: this script's directory)
#   FLAKE_HOST   darwinConfigurations name to build (default: `scutil --get LocalHostName`)
#   NO_GIT_ADD   Set to 1 to skip auto-staging files for the flake.
#
set -euo pipefail

# Ensure nix-command + flakes are available even if nix.conf has not enabled them
# yet. The extra- prefix appends, so existing features are not clobbered.
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${FLAKE_DIR:-$SCRIPT_DIR}"
FLAKE_HOST="${FLAKE_HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
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

main() {
  [ "$(uname -s)" = "Darwin" ] || die "this script only supports macOS (detected: $(uname -s))"
  [ -f "${FLAKE_DIR}/flake.nix" ] || die "no flake.nix found in ${FLAKE_DIR}"

  load_nix_env
  nix_works || die "Nix is not available; run ./ensure-nix.sh first, then re-run this."

  stage_flake_files

  local target="${FLAKE_DIR}#${FLAKE_HOST}"

  case "${ACTION}" in
    check)
      log "Validating flake: ${FLAKE_DIR}"
      nix flake check "${FLAKE_DIR}"
      ;;
    build)
      log "Building (no activation): darwinConfigurations.${FLAKE_HOST}.system"
      nix build --no-link "${FLAKE_DIR}#darwinConfigurations.${FLAKE_HOST}.system"
      log "Build OK - nothing was activated."
      ;;
    switch)
      warn "Activation needs administrator rights and may prompt for a password."
      # Recent nix-darwin elevates privileges itself, so this runs without sudo,
      # which also avoids git 'dubious ownership' errors on the repository. If a
      # version requires root, re-run prefixed with sudo.
      if command -v darwin-rebuild >/dev/null 2>&1; then
        log "Applying: darwin-rebuild switch --flake ${target}"
        darwin-rebuild switch --flake "${target}"
      else
        log "First run - darwin-rebuild not installed yet; bootstrapping via 'nix run nix-darwin'..."
        nix run nix-darwin -- switch --flake "${target}"
      fi
      log "Done. Open a new shell (or run 'exec zsh') to pick up the new environment."
      ;;
    *)
      die "unknown action '${ACTION}' (use: switch | build | check)"
      ;;
  esac
}

main "$@"
