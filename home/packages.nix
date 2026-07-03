# CLI tools, pinned by the flake.
{ pkgs, ... }:
{
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
    mkcert          # locally-trusted dev certs; run `mkcert -install` once manually
    openscreen      # screen recorder (open-source Screen Studio alternative)

    # Project toolchain
    # node is intentionally NOT from nixpkgs: the nixpkgs node build (both
    # `nodejs-slim` and full `nodejs`) crashes Next 16's TypeScript type-check
    # worker — SIGKILL with "File descriptor N … unmanaged mode" warnings —
    # while the official nodejs.org binaries work. Verified 2026-06-23: official
    # 24.15.0 builds clean, nixpkgs 24.15.0 (slim AND full) both crash. So node
    # is managed by nvm, pinned per repo via .nvmrc (sourced in home/shell.nix).
    # nodejs_24      # removed 2026-06-23 -> nvm + .nvmrc
    pnpm_10          # packageManager pnpm@10.x (nixpkgs provides 10.34.0); orchestrates only — builds run `next` under the PATH (nvm) node
    python3          # node-gyp for native modules (node-pty, sharp, ...)
    # bun            # optional: sync:repos + alternate server runtime
  ];
}
