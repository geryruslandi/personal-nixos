{
  config,
  lib,
  ...
}:
let
  # Real filesystem path to this repo's WARP plugin sources.
  pluginReal = "${config.home.homeDirectory}/Projects/personal-nixos/noctalia-plugins/gery/warp";

  mkLink = file: config.lib.file.mkOutOfStoreSymlink "${pluginReal}/${file}";
in
{
  xdg.dataFile = {
    "noctalia/plugins/warp/plugin.toml".source = mkLink "plugin.toml";
    "noctalia/plugins/warp/warp.luau".source = mkLink "warp.luau";
  };
}
