# LinearMouse handles mouse-wheel acceleration; macOS defaults live in darwin/.
{ ... }:
{
  xdg.configFile."linearmouse/linearmouse.json".text = builtins.toJSON {
    schemes = [
      {
        "if".device.category = "mouse";
        pointer.disableAcceleration = true;
        # Fixed lines per wheel tick, on both axes, with no momentum curve.
        scrolling.distance = {
          vertical = 3;
          horizontal = 3;
        };
      }
    ];
  };

  # Home Manager loads this agent during activation, after installing the config.
  # It also starts LinearMouse at each login, without a separate app login item.
  launchd.agents.linearmouse = {
    enable = true;
    config = {
      ProgramArguments = [ "/usr/bin/open" "-ga" "/Applications/LinearMouse.app" ];
      RunAtLoad = true;
    };
  };
}
