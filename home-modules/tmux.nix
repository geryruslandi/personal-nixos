{
  pkgs,
  lib,
  ...
}:
let
  pluginSrc = "${pkgs.tmuxPlugins.tokyo-night-tmux}/share/tmux-plugins/tokyo-night-tmux";
  tmuxRam =
    pkgs.writeShellScript "tmux-ram" ''
      read -r total avail _ < <(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print t, a, ""}' /proc/meminfo)
      pct=$(( (total-avail)*100/total ))
      echo "#[fg=#4fd6be,bg=default]󰍛 ''${pct}% "
    '';
in
{
  home.packages = with pkgs; [
    bc
    gawk
    jq
  ];
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    clock24 = true;
    mouse = true;
    historyLimit = 10000;
    baseIndex = 1;
    keyMode = "vi";

    plugins = [
      {
        plugin = pkgs.tmuxPlugins.tokyo-night-tmux;
        extraConfig = ''
          set -g @tokyo-night-tmux_theme night
          set -g @tokyo-night-tmux_transparent 1
          set -g @tokyo-night-tmux_show_git 1
          set -g @tokyo-night-tmux_show_netspeed 1
          set -g @tokyo-night-tmux_show_battery_widget 1
        '';
      }
    ];

    extraConfig = ''
      set -g extended-keys on
      set -g extended-keys-format csi-u

      # --- Clearer active-tab highlight (loaded after the theme plugin) ---
      set -g window-status-current-format "#[fg=#1a1b26,bg=#7aa2f7,bold,nodim] #{?#{==:#{pane_current_command},ssh},󰣀 ,} #I:#W#{?window_zoomed_flag, 󰊓,} "

      # --- Drop session-name pill from status-left (keep prefix indicator) ---
      set -g status-left "#[fg=#2A2F41,bg=#7aa2f7,bold] #{?client_prefix,󰠠 ,#[dim]󰤂 }"

      # --- RAM widget appended to status-right (plugin 1.8.1 lacks the widget-order option) ---
      set -g status-right "#(${pluginSrc}/src/battery-widget.sh)#(${pluginSrc}/src/path-widget.sh #{pane_current_path})#(${tmuxRam})#(${pluginSrc}/src/netspeed.sh)#(${pluginSrc}/src/git-status.sh #{pane_current_path})#(${pluginSrc}/src/datetime-widget.sh)"
    '';
  };
}
