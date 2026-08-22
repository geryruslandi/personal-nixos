{
  inputs,
  ...
}:
{
  # import the home manager module
  imports = [
    inputs.vicinae.homeManagerModules.default
  ];

  programs.vicinae = {
    enable = true;

    systemd = {
      enable = true;
      autoStart = true;
      # Use the Wayland layer-shell protocol (required on Hyprland)
      environment = {
        USE_LAYER_SHELL = 1;
      };
    };

    settings = {
      close_on_focus_loss = false;
      consider_preedit = true;
      pop_to_root_on_close = true;
      search_files_in_root = true;

      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          size = 12;
        };
      };

      theme = {
        light = {
          name = "catppuccin-frappe";
          icon_theme = "default";
        };
        dark = {
          name = "catppuccin-frappe";
          icon_theme = "default";
        };
      };
      launcher_window = {
        opacity = 0.90;
      };
    };

  };
  # Vicinae is launched as a user systemd service (systemd.enable above);
  # no exec-once entry needed. Third-party extensions would need nodejs.

  # Toggle Vicinae with Super+Space (replaces the Noctalia launcher bind)
  wayland.windowManager.hyprland = {
    settings = {
      bind = [
        "$mainMod, SPACE, exec, vicinae vicinae://toggle"
        "$mainMod, V, exec, vicinae vicinae://launch/clipboard/history"
      ];
    };
  };
}
