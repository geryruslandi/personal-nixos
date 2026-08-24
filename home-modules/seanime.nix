{
  pkgs,
  secrets,
  ...
}:
let
  seanime = secrets.server.seanime or { };
in
{
  # Seanime media server binary. The service itself is declared and managed by
  # the Noctalia plugin (home-sync/.local/share/noctalia/plugins/seanime) via
  # a transient systemd user unit — this module only provides the dependency.
  home.packages = [ pkgs.seanime ];
}
