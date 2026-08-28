{
  pkgs,
  ...
}:
{
  # SonarQube scanner CLI. The server itself is a pair of OCI containers
  # declared in system-modules/sonarqube.nix.
  #
  # Auth reality-check (SonarQube 9.9 LTS): analysis is NEVER anonymous on
  # this server version - api/plugins/installed has required authentication
  # since 9.7 and the scanner always calls it. So `sonar-scanner` needs a
  # login/token. The system module mints a user token on first start and
  # caches it in /var/lib/sonarqube/scanner-token (world-readable on this
  # single-user box; the server is localhost-only). Exporting it as
  # SONAR_TOKEN makes plain `sonar-scanner` just work - no -D flags.
  home.packages = [ pkgs.sonar-scanner-cli ];

  programs.zsh.initExtra = ''
    export SONAR_TOKEN="$(cat /var/lib/sonarqube/scanner-token 2>/dev/null || true)"
  '';
}