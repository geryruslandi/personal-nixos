{
  pkgs,
  ...
}:
{
  # SonarQube scanner CLI. The server itself is a pair of OCI containers
  # declared in system-modules/sonarqube.nix; this module only provides the
  # client so projects can run `sonar-scanner` locally (points at
  # http://localhost:9000 by default; no token needed with
  # SONAR_FORCEAUTHENTICATION=false).
  home.packages = [ pkgs.sonar-scanner-cli ];
}