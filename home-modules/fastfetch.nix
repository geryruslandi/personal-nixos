{
  lib, pkgs, ...
}:
{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        type = "builtin";
        source = "nixos";
        padding = { top = 1; };
      };
      display = {
        separator = " ➜  ";
      };
      modules = [
        "break"
        "break"
        "break"
        {
          type = "os";
          key = "OS   ";
          keyColor = "#8caaee";
        }
        {
          type = "kernel";
          key = " ├  ";
          keyColor = "#8caaee";
        }
        {
          type = "packages";
          format = "{} (nix)";
          key = " ├ 󰏖 ";
          keyColor = "#8caaee";
        }
        {
          type = "shell";
          key = " └  ";
          keyColor = "#8caaee";
        }
        "break"
        {
          type = "wm";
          key = "WM   ";
          keyColor = "#ca9ee6";
        }
        {
          type = "wmtheme";
          key = " ├ 󰉼 ";
          keyColor = "#ca9ee6";
        }
        {
          type = "icons";
          key = " ├ 󰀻 ";
          keyColor = "#ca9ee6";
        }
        {
          type = "cursor";
          key = " ├  ";
          keyColor = "#ca9ee6";
        }
        {
          type = "terminal";
          key = " ├  ";
          keyColor = "#ca9ee6";
        }
        {
          type = "terminalfont";
          key = " └  ";
          keyColor = "#ca9ee6";
        }
        "break"
        {
          type = "host";
          key = "PC   ";
          keyColor = "#a6d189";
        }
        {
          type = "cpu";
          format = "{1} ({3}) @ {7} GHz";
          key = " ├  ";
          keyColor = "#a6d189";
        }
        {
          type = "gpu";
          format = "{1} {2}";
          key = " ├ 󰢮 ";
          keyColor = "#a6d189";
        }
        {
          type = "memory";
          key = " ├  ";
          keyColor = "#a6d189";
        }
        {
          type = "swap";
          key = " ├ 󰓡 ";
          keyColor = "#a6d189";
        }
        {
          type = "disk";
          key = " ├ 󰋊 ";
          keyColor = "#a6d189";
        }
        {
          type = "monitor";
          key = " └  ";
          keyColor = "#a6d189";
        }
        "break"
        "break"
      ];
    };
  };
}
