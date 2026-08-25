{
  pkgs,
  lib,
  inputs,
  config,
  secrets,
  ...
}:
let
  seanime = secrets.server.seanime or { };
  seanimePort = seanime.port or 43211;
  stremio = secrets.server.stremio or { };
  seaweedfs = secrets.server.seaweedfs or { enable = false; };
in
{
  # import the home manager module
  imports = [
    inputs.noctalia.homeModules.default
  ];

  home.file.".face".source = ../home-sync/.config/gery/Pictures/avatar.png;

  # configure options
  programs.noctalia = {
    enable = true;
    settings = {
      accessibility = {
        ui_scale = 1.0;
      };

      shell = {
        font_family = "JetBrainsMono Nerd Font";
        time_format = "{:%H:%M}";
        avatar_path = "~/.face";
        clipboard_enabled = true;
        clipboard_auto_paste = "auto";
        corner_radius_scale = 1.0;
        settings_show_advanced = true;
        show_location = true;
        polkit_agent = false;
        password_style = "default";
        screen_time_enabled = true;

        animation = {
          enabled = true;
          speed = 1.0;
        };

        shadow = {
          direction = "down_right";
          alpha = 0.55;
        };

        panel = {
          transparency_mode = "soft";
          borders = false;
          shadow = true;
          control_center_placement = "floating";
          open_near_click_control_center = true;
          launcher_placement = "floating";
          launcher_position = "center";
          wallpaper_placement = "attached";
          session_placement = "attached";
        };

        launcher = {
          categories = true;
          show_icons = true;
          sort_by_usage = true;
          auto_paste = "auto";

          providers = {
            calculator = {
              prefix = "";
            };
          };
        };

        mpris = {
          blacklist = [ ];
        };
      };

      wallpaper = {
        enabled = true;
        directory = "/home/geryruslandi/.config/gery/Pictures/Wallpapers";
        fill_mode = "crop";
        fill_color = "#000000";
        transition = [
          "fade"
          "wipe"
          "disc"
          "stripes"
          "zoom"
          "honeycomb"
        ];
        transition_duration = 1500;
        edge_smoothness = 0.05;

        default = {
          path = "/home/geryruslandi/.config/gery/Pictures/Wallpapers/firewatch.jpg";
        };

        monitors = {
          "eDP-1" = {
            path = "/home/geryruslandi/.config/gery/Pictures/Wallpapers/firewatch.jpg";
          };
        };

        automation = {
          enabled = false;
          interval_seconds = 600;
          order = "random";
          recursive = false;
        };
      };

      theme = {
        mode = "dark";
        source = "community";
        builtin = "Nord";
        community_palette = "Catppuccin Frappe Blue";
        wallpaper_scheme = "m3-content";

        templates = {
          enable_builtin_templates = true;
          builtin_ids = [
            "gtk3"
            "gtk4"
            "hyprland"
            "kcolorscheme"
            "kitty"
            "qt"
          ];
          enable_community_templates = true;
          community_ids = [
            "opencode"
            "discord"
            "libreoffice"
            "obsidian"
            "vscode"
            "steam"
            "rofi"
            "hyprtoolkit"
            "lazygit"
          ];
        };
      };

      notification = {
        enable_daemon = true;
        show_app_name = true;
        show_actions = true;
        layer = "overlay";
        scale = 1.0;
        background_opacity = 1.0;
        offset_x = 20;
        offset_y = 8;

        filter = {
          firefox = {
            enabled = true;
            match = "firefox";
            play_sound = false;
          };
          chrome = {
            enabled = true;
            match = "chrome";
            play_sound = false;
          };
          chromium = {
            enabled = true;
            match = "chromium";
            play_sound = false;
          };
          edge = {
            enabled = true;
            match = "edge";
            play_sound = false;
          };
        };
      };

      osd = {
        position = "top_right";
        orientation = "horizontal";
        scale = 1.0;
        background_opacity = 1.0;
        offset_x = 20;
        offset_y = 8;

        kinds = {
          volume = true;
          volume_output = true;
          volume_input = true;
          brightness = true;
          wifi = true;
          bluetooth = true;
          power_profile = true;
          caffeine = true;
          nightlight = true;
          dnd = true;
          lock_keys = true;
          keyboard_layout = true;
          privacy = true;
        };
      };

      lockscreen = {
        enabled = true;
      };

      lockscreen_widgets = {
        enabled = false;
        widget_order = [ "lockscreen-login-box@eDP-1" ];

        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };

        widget = {
          "lockscreen-login-box@eDP-1" = {
            type = "login_box";
            output = "eDP-1";
            cx = 864.0;
            cy = 898.0;
            box_width = 810.0;
            box_height = 196.0;
            rotation = 0.0;

            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
          };
        };
      };

      system = {
        monitor = {
          enabled = true;
          cpu_poll_seconds = 3.0;
          gpu_poll_seconds = 5.0;
          memory_poll_seconds = 3.0;
          network_poll_seconds = 3.0;
          disk_poll_seconds = 3.0;
        };
      };

      calendar = {
        enabled = true;
        refresh_minutes = 15;
      };

      weather = {
        enabled = true;
        refresh_minutes = 30;
        unit = "metric";
        effects = true;
      };

      location = {
        address = "Batam, Indonesia";
      };

      audio = {
        enable_overdrive = false;
        enable_sounds = true;
        sound_volume = 0.5;
      };

      brightness = {
        enable_ddcutil = false;
      };

      nightlight = {
        enabled = false;
        force = false;
        temperature_day = 6500;
        temperature_night = 4000;
      };

      idle = {
        pre_action_fade_seconds = 5;

        behavior = {
          lock = {
            timeout = 600;
            action = "lock";
            enabled = true;
          };
          "screen-off" = {
            timeout = 300;
            action = "screen_off";
            enabled = true;
          };
          suspend = {
            timeout = 1800;
            action = "lock_and_suspend";
            enabled = true;
          };
        };
      };

      bar = {
        order = [
          "main"
        ];

        main = {
          position = "top";
          background_opacity = 0.2;
          capsule = true;
          capsule_opacity = 0.46;
          capsule_radius = 7;
          color = "primary";
          icon_color = "primary";
          concave_edge_corners = false;
          margin_ends = 0;
          radius = 0;
          radius_bottom_left = 6;
          radius_bottom_right = 6;
          shadow = true;
          reserve_space = true;
          auto_hide = false;
          font_family = "JetBrainsMono Nerd Font Propo";
          start = [
            "services"
            "bar"
            "privacy"
            "active_window"
          ];
          center = [ "workspaces" ];
          end = [
            "group:g1"
            "group:g2"
            "tray"
            "volume"
            "widget"
            "clock"
            "control-center"
          ];
          capsule_group = [
            {
              accordion = true;
              accordion_direction = "end";
              enabled = true;
              fill = "surface_variant";
              id = "g1";
              members = [
                "temp"
                "cpu"
                "ram"
              ];
              opacity = 0.46;
              padding = 6.0;
              radius = 7.0;
            }
            {
              accordion = true;
              accordion_direction = "end";
              enabled = true;
              fill = "surface_variant";
              id = "g2";
              members = [
                "network_rx"
                "network_tx"
              ];
              opacity = 0.46;
              padding = 6.0;
              radius = 7.0;
            }
          ];
        };
      };

      dock = {
        enabled = false;
      };

      desktop_widgets = {
        enabled = false;
        widget_order = [ "desktop-widget-0000000000000001" ];
        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };
        widget = {
          "desktop-widget-0000000000000001" = {
            type = "yugaaank/better-clock:clock";
            output = "eDP-1";
            cx = 990.0;
            cy = 666.0;
            box_width = 272.0;
            box_height = 272.0;
            rotation = 0.0;
          };
        };
      };

      control_center = {
        show_shortcut_labels = true;

        calendar = {
          event_date_format = "%e %A %B";
          show_events_card = false;
          show_week_numbers = false;
        };

        shortcuts = [
          {
            type = "wifi";
          }
          {
            type = "bluetooth";
          }
          {
            type = "noctalia/screen_recorder:toggle";
          }
          {
            type = "notification";
          }
          {
            type = "nightlight";
          }
          {
            type = "caffeine";
          }
        ];
      };

      hooks = { };

      widget = {
        active_window = {
          max_length = 200;
          title_scroll = "on_hover";
          display = "icon_and_text";
        };
        temp = {
          type = "sysmon";
          stat = "cpu_temp";
        };
        ram = {
          type = "sysmon";
          stat = "ram_used";
        };
        network_rx = {
          capsule = true;
          network_speed_compact = true;
          visualization = "none";
        };
        network_tx = {
          network_speed_compact = true;
          visualization = "none";
        };
        media = {
          hide_when_no_media = true;
        };
        clock = {
          format = "%d/%m/%Y %H:%M";
        };
        privacy = {
          hide_inactive = true;
        };
        "bar" = {
          style = "label";
          type = "felipeartur/ai-usagebar:bar";
          vendor = "openrouter";
        };
        "rec" = {
          type = "noctalia/screen_recorder:recorder";
        };
        "w-engine" = {
          type = "tadomika_ari/w-engine:w-engine-widget";
        };
        "services" = {
          type = "gery/services:services";
        };
        "todo" = {
          type = "nightwatch75/todo:todo";
        };
        "widget" = {
          type = "piero-93/battery-power-management:widget";
        };
      };

      plugins = {
        enabled = [
          "noctalia/screen_recorder"
          "noctalia/wallhaven"
          "ycf/mawaqit"
          "noctalia/bitwarden"
          "noctalia/notes"
          "dunarand/tmux-provider"
          "nightwatch75/todo"
          "tadomika_ari/w-engine"
          "gery/services"
          "felipeartur/ai-usagebar"
          "piero-93/battery-power-management"
          "jamesfeeder/special-workspaces"
        ];
        auto_update = "all";
      };

      plugin_settings = {
        "felipeartur/ai-usagebar" = {
          panel_open_near_click = true;
          panel_placement = "floating";
        };
        "nightwatch75/todo" = {
          panel_placement = "floating";
          panel_position = "center";
        };
        "piero-93/battery-power-management" = {
          panel_placement = "floating";
        };
        "gery/services" = {
          services-panel_placement = "floating";
          # Only ports the plugin actually passes on a start command line
          # (mailpit, seanime) are configurable; string-typed because int
          # settings render as a 0-100 slider in the Settings UI. System
          # service listeners keep coming from secrets.* via Nix modules.
          mailpit_smtpPort = toString ((secrets.server or { }).mailpit.smtpPort or 1025);
          mailpit_uiPort = toString ((secrets.server or { }).mailpit.uiPort or 8025);
          mailpit_auto_start = (secrets.server or { }).mailpit.enable or false;
          seanime_port = toString seanimePort;
          seanime_auto_start = seanime.enable or false;
          stremio_auto_start = stremio.enable or false;
        };
      };
    };
  };

  home.packages = with pkgs; [
    gpu-screen-recorder
    linux-wallpaperengine
    ffmpeg
  ];

  # Keybinds
  wayland.windowManager.hyprland = {
    settings = {
      bind = [
        "$mainMod, R, exec, noctalia msg panel-toggle control-center"
        "$mainMod, comma, exec, noctalia msg settings-toggle"
        "$mainMod, L, exec, noctalia msg session lock"
        ", XF86PowerOff, exec, noctalia msg panel-toggle session"
      ];
    };
  };
}
