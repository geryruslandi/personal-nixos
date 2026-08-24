{
  pkgs,
  ...
}:
{
  # Mailpit dev mail tool binary. The service itself is declared and managed
  # by the Noctalia plugin (home-sync/.local/share/noctalia/plugins/mailpit)
  # via a transient systemd user unit — this module only provides the
  # dependency.
  home.packages = [ pkgs.mailpit ];
}
