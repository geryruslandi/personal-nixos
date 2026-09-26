{
  pkgs,
  lib,
  config,
  ...
}:
let
  tokenFile = "${config.xdg.stateHome}/sonarqube/scanner-token";
in
{
  # SonarQube scanner CLI. The server itself is a pair of user-level OCI
  # containers declared in home-modules/sonarqube.nix.
  #
  # Auth reality-check (SonarQube 9.9 LTS): analysis is NEVER anonymous on
  # this server version - api/plugins/installed has required authentication
  # since 9.7 and the scanner always calls it. The user-level wrapper mints a
  # user token on first start and caches it in
  # ~/.local/state/sonarqube/scanner-token (single-user box; the server is
  # localhost-only). Exporting it as SONAR_TOKEN makes plain `sonar-scanner`
  # just work - no -D flags.
  home.packages = [ pkgs.sonar-scanner-cli ];

  programs.zsh.initContent = lib.mkAfter ''
    export SONAR_TOKEN="$(cat ${tokenFile} 2>/dev/null || true)"
  '';
}
