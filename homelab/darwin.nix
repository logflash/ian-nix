# Only the explicit homelab profile installs VM software and runs the tunnel.
{ lib, pkgs, username, namespace, ... }:
let
  tunnelConfig = "/Users/${username}/.config/${namespace}/cloudflared.json";
  startTunnel = pkgs.writeShellScript "start-homelab-cloudflared" ''
    # A fresh machine has no tunnel until interactive setup has run.
    while [ ! -s ${lib.escapeShellArg tunnelConfig} ]; do
      /bin/sleep 10
    done
    exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate \
      --config ${lib.escapeShellArg tunnelConfig} run
  '';
in {
  homebrew.casks = [ "utm" ];

  environment.systemPackages = [ pkgs.cloudflared ];
  launchd.daemons."${namespace}-cloudflared".serviceConfig = {
    Label = "org.${namespace}.cloudflared";
    ProgramArguments = [ "${startTunnel}" ];
    UserName = username;
    EnvironmentVariables.HOME = "/Users/${username}";
    RunAtLoad = true;
    KeepAlive = true;
  };
}
