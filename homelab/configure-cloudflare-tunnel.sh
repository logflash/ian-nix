#!/usr/bin/env bash
# Interactive, locally managed Cloudflare Tunnel setup for the homelab Mac.
# Credentials and prompted routes stay in the user's home, outside the flake.
set -euo pipefail
umask 077

ACTION="${1:-ensure}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
namespace="${DARWIN_CONFIG_NAMESPACE:-$(basename "$(dirname "$script_dir")")}"
config_dir="${HOME}/.config/${namespace}"
config_file="${config_dir}/cloudflared.json"
credentials_dir="${HOME}/.cloudflared"
service_label="org.${namespace}.cloudflared"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "$ACTION" in
  ensure|add) ;;
  *) die "unknown tunnel action: $ACTION" ;;
esac
[[ "$namespace" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid DARWIN_CONFIG_NAMESPACE"

command -v jq >/dev/null 2>&1 || die "jq is missing; run ./configure-homelab.sh first"
if [ -n "${CLOUDFLARED_BIN:-}" ]; then
  cloudflared="$CLOUDFLARED_BIN"
elif [ -x /run/current-system/sw/bin/cloudflared ]; then
  cloudflared=/run/current-system/sw/bin/cloudflared
else
  cloudflared="$(command -v cloudflared || true)"
fi
[ -n "$cloudflared" ] && [ -x "$cloudflared" ] || die "cloudflared is missing; run ./configure-homelab.sh first"

ensure_credentials() {
  if [ ! -e "$credentials_file" ] && [ ! -L "$credentials_file" ]; then
    [ -s "$credentials_dir/cert.pem" ] || die "Cloudflare login certificate is missing; run cloudflared tunnel login"
    log "Recovering local credentials for existing tunnel $tunnel_id."
    "$cloudflared" tunnel token --cred-file "$credentials_file" "$tunnel_id" >/dev/null ||
      die "could not recover credentials for tunnel $tunnel_id"
  fi
  [ -f "$credentials_file" ] && [ ! -L "$credentials_file" ] ||
    die "tunnel credentials are missing or invalid: $credentials_file"
  chmod 600 "$credentials_file"
  jq -e --arg id "$tunnel_id" '
    .TunnelID == $id and
    (.TunnelSecret | type == "string") and
    (.AccountTag | type == "string")
  ' "$credentials_file" >/dev/null || die "invalid tunnel credentials: $credentials_file"
}

validate_config() {
  [ -f "$config_file" ] && [ ! -L "$config_file" ] || die "unexpected tunnel config at $config_file"
  jq -e '
    (.tunnel | type == "string") and
    (."credentials-file" | type == "string") and
    (.ingress | type == "array") and
    (.ingress[-1].service == "http_status:404")
  ' "$config_file" >/dev/null || die "invalid tunnel config at $config_file"
  tunnel_id="$(jq -er '.tunnel' "$config_file")"
  credentials_file="$(jq -er '."credentials-file"' "$config_file")"
  ensure_credentials
  "$cloudflared" tunnel --config "$config_file" ingress validate >/dev/null
}

prompt() {
  printf '%s' "$1" >&2
  IFS= read -r REPLY || die "could not read from the terminal"
}

validate_hostname() {
  local label
  [[ "$1" == *.* && "$1" =~ ^[a-z0-9.-]+$ && ${#1} -le 253 ]] || die "enter a full DNS hostname, such as app.example.com"
  local IFS=.
  read -r -a labels <<< "$1"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 && "$label" != -* && "$label" != *- ]] || die "invalid DNS label in $1"
  done
}

existing=false
if [ -e "$config_file" ] || [ -L "$config_file" ]; then
  validate_config
  existing=true
  if [ "$ACTION" = ensure ]; then
    log "Cloudflare Tunnel is already configured (ID $tunnel_id); skipping setup."
    exit 0
  fi
fi

if [ ! -t 0 ]; then
  if [ "$ACTION" = ensure ]; then
    warn "Cloudflare Tunnel is not configured; run ./configure-homelab.sh tunnel in an interactive terminal."
    exit 0
  fi
  die "tunnel setup needs an interactive terminal"
fi

log "Cloudflare Tunnel setup. Your domain must already use Cloudflare DNS."
if [ "$existing" = false ]; then
  default_name="$(hostname -s)-homelab"
  prompt "Tunnel name [$default_name]: "
  tunnel_name="${REPLY:-$default_name}"
  [[ "$tunnel_name" =~ ^[A-Za-z0-9_-]+$ ]] || die "tunnel name can contain only letters, digits, _ and -"
fi

prompt "Public hostname (Enter to skip tunnel setup): "
hostname="$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]')"
[ -n "$hostname" ] || { log "Tunnel setup skipped."; exit 0; }
validate_hostname "$hostname"

prompt "Local service URL (for example, http://localhost:3000): "
origin="$REPLY"
[[ "$origin" =~ ^(http|https|ssh|tcp)://[^[:space:]]+$ ]] || die "use an http, https, ssh, or tcp service URL"

if [ "$existing" = true ]; then
  prior_origin="$(jq -r --arg host "$hostname" '.ingress[] | select(.hostname? == $host) | .service' "$config_file")"
  if [ -n "$prior_origin" ]; then
    [ "$prior_origin" = "$origin" ] || die "$hostname already routes to $prior_origin; edit the existing route deliberately"
    log "$hostname already routes to $origin; nothing to change."
    exit 0
  fi
fi

printf 'Publishing %s to %s makes it reachable on the Internet unless you add a Cloudflare Access policy.\n' "$hostname" "$origin"
prompt "Type PUBLISH to create the Cloudflare DNS route: "
[ "$REPLY" = PUBLISH ] || { log "Tunnel setup skipped."; exit 0; }

if [ "$existing" = false ]; then
  if [ ! -s "$credentials_dir/cert.pem" ]; then
    log "Opening Cloudflare login in your browser."
    "$cloudflared" tunnel login
  fi
  [ -s "$credentials_dir/cert.pem" ] || die "Cloudflare login did not create $credentials_dir/cert.pem"
  chmod 600 "$credentials_dir/cert.pem"

  tunnel_list="$("$cloudflared" tunnel list --output json --name "$tunnel_name")"
  tunnel_id="$(jq -r --arg name "$tunnel_name" '[(. // [])[] | select(.name == $name) | .id] | unique | .[]' <<< "$tunnel_list")"
  if [ -z "$tunnel_id" ]; then
    log "Creating Cloudflare Tunnel $tunnel_name."
    "$cloudflared" tunnel create "$tunnel_name"
    tunnel_list="$("$cloudflared" tunnel list --output json --name "$tunnel_name")"
    tunnel_id="$(jq -r --arg name "$tunnel_name" '[(. // [])[] | select(.name == $name) | .id] | unique | .[]' <<< "$tunnel_list")"
  fi
  [[ "$tunnel_id" =~ ^[0-9a-fA-F-]{36}$ ]] || die "could not identify the tunnel UUID; inspect cloudflared tunnel list"
  credentials_file="$credentials_dir/$tunnel_id.json"
  ensure_credentials
fi

mkdir -p "$config_dir"
candidate="$(mktemp "$config_dir/cloudflared.XXXXXX")"
trap 'rm -f "$candidate"' EXIT
if [ "$existing" = true ]; then
  jq --arg host "$hostname" --arg service "$origin" \
    '.ingress |= (.[0:-1] + [{hostname: $host, service: $service}] + [.[-1]])' \
    "$config_file" > "$candidate"
else
  jq -n --arg id "$tunnel_id" --arg credentials "$credentials_file" \
    --arg host "$hostname" --arg service "$origin" \
    '{tunnel: $id, "credentials-file": $credentials,
      ingress: [{hostname: $host, service: $service}, {service: "http_status:404"}]}' > "$candidate"
fi
"$cloudflared" tunnel --config "$candidate" ingress validate

# Never overwrite an unrelated DNS record. If this fails, the local config is
# unchanged and a rerun reuses the tunnel rather than creating another one.
dns_status="$(python3 "$(dirname "$0")/cloudflare-dns-status.py" "$hostname" "$tunnel_id")" ||
  die "could not verify Cloudflare DNS; no route was changed"
case "$dns_status" in
  matching)
    log "DNS already routes $hostname to this tunnel; keeping the existing record."
    ;;
  missing)
    log "Creating DNS route for $hostname."
    "$cloudflared" tunnel route dns "$tunnel_id" "$hostname"
    ;;
  conflict)
    die "$hostname already has an A, AAAA, or CNAME record that does not route to this tunnel. Use another hostname or deliberately change that record in Cloudflare DNS."
    ;;
  *) die "unexpected Cloudflare DNS status: $dns_status" ;;
esac
mv "$candidate" "$config_file"
trap - EXIT
chmod 600 "$config_file"

if launchctl print "system/$service_label" >/dev/null 2>&1; then
  if [ "$existing" = false ]; then
    log "Connector will start automatically when it sees the new config."
  elif ! sudo launchctl kickstart -k "system/$service_label"; then
    warn "Route saved, but the connector could not restart. Run: sudo launchctl kickstart -k system/$service_label"
  fi
else
  warn "Connector is not installed yet; run ./configure-homelab.sh to start it."
fi
log "Configured $hostname -> $origin through tunnel $tunnel_id."
