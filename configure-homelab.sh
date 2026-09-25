#!/usr/bin/env bash
# Apply the shared Darwin configuration with homelab additions, then provision
# the pinned Ubuntu Server installer and UTM VM. Run as a regular user.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-switch}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "homelab setup requires macOS"
[ "$(uname -m)" = arm64 ] || die "the declared Ubuntu ARM64 VM requires an Apple Silicon Mac"
[ "$(id -u)" -ne 0 ] || die "run this script as your regular user, without sudo"

case "$ACTION" in
  switch|build|check|vm|finish) ;;
  *) die "unknown action '$ACTION' (use: switch | build | check | vm | finish)" ;;
esac

if [ "$ACTION" != vm ] && [ "$ACTION" != finish ]; then
  FLAKE_CONFIG=homelab "$SCRIPT_DIR/configure-darwin.sh" "$ACTION"
  [ "$ACTION" = switch ] || exit 0
fi

# The Darwin wrapper loads Nix in its own process; do the same before reading
# the VM declaration (a fresh login shell is not required).
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if [ -e "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]; then
  # shellcheck disable=SC1091
  . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
fi

command -v jq >/dev/null 2>&1 || die "jq is missing after activation; open a new shell and re-run this script"
command -v nix >/dev/null 2>&1 || die "nix is missing after activation"
command -v osascript >/dev/null 2>&1 || die "osascript is required to create the UTM VM"
[ -d /Applications/UTM.app ] || die "UTM did not install; check the Homebrew output above"

vm_json="$(nix eval --json --file "$SCRIPT_DIR/homelab/vm.nix")"
vm_name="$(jq -r '.name' <<<"$vm_json")"
ram_mib="$(jq -r '.memoryMiB' <<<"$vm_json")"
cpu_cores="$(jq -r '.cpuCores' <<<"$vm_json")"
disk_mib="$(jq -r '.diskGiB * 1024' <<<"$vm_json")"
iso_url="$(jq -r '.iso.url' <<<"$vm_json")"
iso_sha256="$(jq -r '.iso.sha256' <<<"$vm_json")"
iso_file="${iso_url##*/}"
# The verified download is moved into the VM bundle before its first boot.
cache_dir="${HOME}/Library/Containers/com.utmapp.UTM/Data/Documents/Installers"
iso_path="${cache_dir}/${iso_file}"
vm_bundle="${HOME}/Library/Containers/com.utmapp.UTM/Data/Documents/${vm_name}.utm"
vm_data="${vm_bundle}/Data"
vm_config="${vm_bundle}/config.plist"
internal_iso="${vm_data}/${iso_file}"
ready_marker="${vm_data}/.ian-nix-ready"

verify_vm_disk() {
  # UTM's AppleScript API omits the logical size of an existing sparse disk.
  # UTM gives us the disk ID, so check its exact file without enumerating the
  # protected app-data directory.
  local disk_id="$1"
  local expected_bytes=$((disk_mib * 1024 * 1024))
  local disk_file="${vm_data}/${disk_id}.img"
  [ -f "$disk_file" ] || die "cannot find UTM disk image: $disk_file"
  [ "$(stat -f %z "$disk_file")" -eq "$expected_bytes" ] || die "UTM disk size differs from declared ${disk_mib} MiB"
}

require_all_vms_stopped() {
  local active_vms
  active_vms="$(/Applications/UTM.app/Contents/MacOS/utmctl list | awk 'NR > 1 && $2 != "stopped" { print }')"
  [ -z "$active_vms" ] || die "stop running UTM VMs before changing VM boot media: $active_vms"
}

finalize_vm() {
  require_all_vms_stopped
  [ -f "$vm_config" ] || die "cannot find UTM config: $vm_config"
  [ -f "$internal_iso" ] || [ -f "$iso_path" ] || die "verified Ubuntu installer is missing"

  # UTM's Apple backend requires a security-scoped bookmark for an external
  # ISO, which AppleScript cannot supply. Put it inside the VM bundle and
  # declare it as an internal read-only drive instead.
  log "Finalizing UTM boot media and installer input devices."
  osascript -e 'tell application "UTM" to quit'
  if [ ! -f "$internal_iso" ]; then mv "$iso_path" "$internal_iso"; fi
  if ! plutil -extract Drive.0.ImageName raw "$vm_config" >/dev/null 2>&1; then
    plutil -insert Drive.0.ImageName -string "$iso_file" "$vm_config"
  fi
  plutil -replace Virtualization.Keyboard -string Generic "$vm_config"
  plutil -replace Virtualization.Pointer -string Mouse "$vm_config"
  touch "$ready_marker"
  open -a /Applications/UTM.app
}

vm_status="$(osascript "$SCRIPT_DIR/homelab/create-utm-vm.applescript" "$vm_name" "$iso_path" "$ram_mib" "$cpu_cores" "$disk_mib" check)"
if [ "$ACTION" = finish ]; then
  [ "${vm_status%%:*}" = existing ] || die "UTM VM does not exist: $vm_name"
  verify_vm_disk "${vm_status#existing:}"
  [ -f "$ready_marker" ] || die "VM setup has not finished yet"
  mounted_iso="$(plutil -extract Drive.0.ImageName raw "$vm_config" 2>/dev/null || true)"
  if [ "$mounted_iso" != "$iso_file" ]; then
    log "Installer drive is already removed."
    exit 0
  fi
  require_all_vms_stopped
  osascript -e 'tell application "UTM" to quit'
  plutil -remove Drive.0 "$vm_config"
  open -a /Applications/UTM.app
  log "Removed the Ubuntu installer drive. The installed VM can now boot from its disk."
  exit 0
fi

if [ "$vm_status" != missing ]; then
  verify_vm_disk "${vm_status#existing:}"
  if [ ! -f "$ready_marker" ] && { [ -f "$iso_path" ] || [ -f "$internal_iso" ]; }; then
    finalize_vm
  fi
  log "Existing UTM VM matches declared backend, RAM, and CPUs: $vm_name"
  log "UTM disk size matches declared ${disk_mib} MiB."
  exit 0
fi

mkdir -p "$cache_dir"
if [ -f "$iso_path" ] && [ "$(shasum -a 256 "$iso_path" | cut -d ' ' -f 1)" != "$iso_sha256" ]; then
  die "cached installer checksum is wrong: $iso_path (remove it manually and re-run)"
fi
if [ ! -f "$iso_path" ]; then
  log "Downloading Ubuntu Server ARM64 installer (about 3.6 GB)."
  curl --fail --location --retry 3 --continue-at - --output "${iso_path}.part" "$iso_url"
  actual_sha256="$(shasum -a 256 "${iso_path}.part" | cut -d ' ' -f 1)"
  [ "$actual_sha256" = "$iso_sha256" ] || die "Ubuntu installer checksum mismatch; partial file left at ${iso_path}.part"
  mv "${iso_path}.part" "$iso_path"
fi

log "Creating or checking UTM VM: $vm_name"
osascript "$SCRIPT_DIR/homelab/create-utm-vm.applescript" "$vm_name" "$iso_path" "$ram_mib" "$cpu_cores" "$disk_mib" create
vm_status="$(osascript "$SCRIPT_DIR/homelab/create-utm-vm.applescript" "$vm_name" "$iso_path" "$ram_mib" "$cpu_cores" "$disk_mib" check)"
[ "${vm_status%%:*}" = existing ] || die "UTM VM creation could not be verified"
verify_vm_disk "${vm_status#existing:}"
finalize_vm
log "VM is ready in UTM with Ubuntu Server installer attached. Start it in UTM and complete the Ubuntu installer using username ian."
