{
  pkgs,
  lib,
  ...
}:
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    clock24 = true;
    mouse = true;
    historyLimit = 10000;
    baseIndex = 1;
    keyMode = "vi";

    extraConfig = ''
      # Pass through Kitty keyboard protocol sequences (e.g. Shift+Enter)
      set -g extended-keys on

      # --- Simple Catppuccin (Frappe) theme ---
      set -g status-style               "fg=#c6d0f5,bg=#303446"
      set -g status-left                "#[fg=#ca9ee6,bold] #S "
      set -g status-right               "#[fg=#a6d189] %H:%M %d-%b "
      set -g window-status-style        "fg=#c6d0f5,bg=#303446"
      set -g window-status-current-style "fg=#303446,bg=#ca9ee6"
      set -g pane-border-style          "fg=#414559"
      set -g pane-active-border-style   "fg=#8caaee"
      set -g message-style              "fg=#303446,bg=#ca9ee6"
      set -g mode-style                 "fg=#303446,bg=#ca9ee6"
    '';
  };
}
