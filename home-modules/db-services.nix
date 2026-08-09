{
  config,
  lib,
  secrets,
  ...
}:
let
  services = [ "redis" "mysql" "postgresql" "mailpit" ];
  pluginReal = svc: "${secrets.projectPath}/noctalia-plugins/gery/${svc}";
  mkLink = real: file: config.lib.file.mkOutOfStoreSymlink "${real}/${file}";
in
{
  # Real filesystem path to this repo's service-toggle plugin sources.
  # Each plugin lives in a dir matching the id part after `/` (gery/<svc>).
  xdg.dataFile = builtins.listToAttrs (lib.flatten (map (svc:
    let
      real = pluginReal svc;
    in
    [
      {
        name = "noctalia/plugins/${svc}/plugin.toml";
        value.source = mkLink real "plugin.toml";
      }
      {
        name = "noctalia/plugins/${svc}/${svc}.luau";
        value.source = mkLink real "${svc}.luau";
      }
      {
        name = "noctalia/plugins/${svc}/translations/en.json";
        value.source = mkLink real "translations/en.json";
      }
    ]) services));
}
