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

    # Project toolchain
    nodejs_24        # engines.node ^24.13.1 (nixpkgs provides 24.15.0)
    pnpm_10          # packageManager pnpm@10.x (nixpkgs provides 10.34.0)
    python3          # node-gyp for native modules (node-pty, sharp, ...)
    # bun            # optional: sync:repos + alternate server runtime
  ];
}
