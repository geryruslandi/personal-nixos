# SonarQube stack — fully Home-Manager / user-level after the secrets.server
# removal. Two containers (sonar-postgres backend + the SonarQube app) driven
# by `docker compose` against the ROOTLESS user daemon (system-modules/
# docker.nix), started/stopped by the services hub plugin through the
# gery-sonarqube-dev wrapper.
#
# Unit contract with the plugin (`kind = "transient"`, unit sonarqube.service):
#   start  → transient unit runs the wrapper: idempotent preflight (dirs +
#            generated DB password in ~/.local/state/sonarqube/.db.env),
#            `compose up -d --wait`, one-shot scanner-token mint, then
#            `exec compose up sonarqube` which attaches to the app container
#            in the FOREGROUND. systemd then:
#             * SIGTERM on stop → compose stops its containers (cgroup kill),
#             * app crash → exit code → Restart=on-failure.
# Web port is plugin-editable: passed as SONARQUBE_WEB_PORT and interpolated
# by compose ("127.0.0.1:${SONARQUBE_WEB_PORT:-9000}:9000").
#
# Auth reality-check (SonarQube Community Build 25.x): api/plugins/installed
# has required authentication since 9.7 — a truly anonymous analysis is
# impossible; SONAR_FORCEAUTHENTICATION does nothing as an env var
# (case-insensitive mapping never matches camelCase). Forced authentication
# therefore stays ON and the wrapper mints a scanner token on first start via
# bootstrap admin (admin:admin) — cached in ~/.local/state/sonarqube/
# scanner-token and read by home-modules/sonar.nix (SONAR_TOKEN).
{
  pkgs,
  config,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/sonarqube";
  envFile = "${stateDir}/.db.env";
  tokenFile = "${stateDir}/scanner-token";
  composeFile = "${config.xdg.configHome}/sonarqube/compose.yaml";

  compose = pkgs.formats.yaml { };
in
{
  home.packages = with pkgs; [
    docker-compose
    curl
  ];

  xdg.configFile."sonarqube/compose.yaml".source = compose.generate "compose.yaml" {
    networks = {
      sonar-net = { };
    };
    volumes = {
      "sonar-pgdata" = { };
    };
    services = {
      # Backend DB. Lifecycle is owned by the unit, not by docker restart
      # policies (orphan-prevention — compose `up` foreground controls it).
      sonar-postgres = {
        image = "postgres:16-alpine";
        networks = [ "sonar-net" ];
        env_file = [ envFile ];
        environment = {
          POSTGRES_USER = "sonarqube";
          POSTGRES_DB = "sonarqube";
        };
        volumes = [ "sonar-pgdata:/var/lib/postgresql/data" ];
        healthcheck = {
          test = [ "CMD-SHELL" "pg_isready -U sonarqube -d sonarqube" ];
          interval = "10s";
          timeout = "5s";
          retries = 12;
        };
      };

      sonarqube = {
        # 25.x = SonarQube Community Build (calendar versioning). Pinned exact
        # tag for reproducible start; 25.x bundles eslint-bridge with TS 5.x
        # required by modern tsconfig options.
        image = "sonarqube:25.10.0.114319-community";
        depends_on = {
          sonar-postgres.condition = "service_healthy";
        };
        networks = [ "sonar-net" ];
        env_file = [ envFile ];
        environment = {
          SONAR_JDBC_URL = "jdbc:postgresql://sonar-postgres:5432/sonarqube";
          SONAR_JDBC_USERNAME = "sonarqube";
          # NO SONAR_FORCEAUTHENTICATION here — it doesn't apply (see header).
        };
        volumes = [
          "${stateDir}/data:/opt/sonarqube/data"
          "${stateDir}/logs:/opt/sonarqube/logs"
          "${stateDir}/extensions:/opt/sonarqube/extensions"
        ];
        # localhost-only bind; web port comes from the plugin setting.
        ports = [ "127.0.0.1:\${SONARQUBE_WEB_PORT:-9000}:9000" ];
      };
    };
  };

  xdg.configFile."gery-dev-scripts/gery-sonarqube-dev" = {
    executable = true;
    text = ''
      #!/bin/sh
      # SonarQube stack runner for the services hub plugin.
      #   gery-sonarqube-dev [--port N]
      # 1) idempotent preflight (dirs + generated DB password)
      # 2) `compose up -d --wait` (health-wait for both containers)
      # 3) one-shot scanner token mint (idempotent)
      # 4) `exec compose up sonarqube` — foreground attach: systemd SIGTERM
      #    cleanly stops the stack, app crash fails the unit (on-failure).
      # First ever start may take several minutes (image pull + Spring boot).
      set -eu
      usage() { echo "usage: gery-sonarqube-dev [--port N]" >&2; exit 1; }

      port=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --port) port="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$port" ] || port=9000

      homeDir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state="$homeDir/sonarqube"
      compose="''${XDG_CONFIG_HOME:-$HOME/.config}/sonarqube/compose.yaml"

      mkdir -p "$state/data" "$state/logs" "$state/extensions"

      # Generated DB unit-secret — machine-local state file, never in secrets.nix.
      if [ ! -s "$state/.db.env" ]; then
        pass=$("${pkgs.openssl}/bin/openssl" rand -hex 16)
        umask 077
        printf 'POSTGRES_PASSWORD=%s\nSONAR_JDBC_PASSWORD=%s\n' "$pass" "$pass" > "$state/.db.env"
      fi

      dc() {
        DOCKER_HOST="''${DOCKER_HOST:-unix://''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock}" \
          "${pkgs.docker-compose}/bin/docker-compose" -f "$compose" --project-directory "$state" "$@"
      }
      export SONARQUBE_WEB_PORT="$port"

      dc up -d --wait sonarqube

      # Scanner token, minted once via the bootstrap admin (up to 4 min WAIT
      # for first-start JVM boot). Already minted → skip.
      if [ ! -s "$state/scanner-token" ]; then
        i=0
        while :; do
          i=$((i + 1))
          if [ "$i" -ge 120 ]; then
            echo "gery-sonarqube-dev: web UI did not come up in 240s" >&2
            exit 1
          fi
          if "${pkgs.curl}/bin/curl" -fsS -m 2 "http://127.0.0.1:$port/api/system/status" 2>/dev/null | grep -q '"status":"UP"'; then
            break
          fi
          sleep 2
        done
        token=$("${pkgs.curl}/bin/curl" -fsS -m 2 -u admin:admin -X POST \
          "http://127.0.0.1:$port/api/user_tokens/generate" \
          --data-urlencode "login=admin" \
          --data-urlencode "name=sonar-scanner" \
          | "${pkgs.python3}/bin/python3" -c 'import sys,json;print(json.load(sys.stdin)["token"])')
        umask 022
        printf '%s\n' "$token" > "$state/scanner-token"
      fi

      # Attach in foreground: log streaming, SIGTERM stops the whole stack.
      exec dc up sonarqube
    '';
  };
}
