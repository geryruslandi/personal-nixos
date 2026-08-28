{ config, pkgs, lib, ... }:
let
  dataDir = "/var/lib/sonarqube";
  envFile = "${dataDir}/.db.env";
  dockerPkg = config.virtualisation.docker.package;
  # Scanner token (user token for admin) used by `sonar-scanner` on this host.
  # Generated once at provision time and cached here so the module stays
  # idempotent across reboots. Read by sonar-scanner via `sonar.login` /
  # `SONAR_TOKEN` (Basic auth) - DO NOT store in sonar-project.properties.
  tokenFile = "${dataDir}/scanner-token";
in
{
  # Global SonarQube server (Community) as two OCI containers:
  #   sonar-postgres (postgres:16-alpine) backend + the sonarqube app itself.
  # Uses the docker backend - so both live on the shared docker.service; if
  # Docker is toggled off via the Services Hub, these go down with it.
  # autoStart = false -> registered but never boots; start/stop via the
  # Services Hub (passwordless, see polkit.nix) or `systemctl start
  # docker-sonarqube`.
  #
  # Auth reality-check (SonarQube 9.9 LTS):
  #   * api/plugins/installed has required authentication since 9.7, so a
  #     truly anonymous *analysis* is impossible on this server - the scanner
  #     always needs a login/token.
  #   * SONAR_FORCEAUTHENTICATION=false as an env var does NOT work here:
  #     SonarQube maps env vars to properties case-insensitively
  #     (SONAR_FORCEAUTHENTICATION -> sonar.forceauthentication), which never
  #     matches the real camelCase property sonar.forceAuthentication, so it
  #     is silently ignored and forced authentication stays ON.
  #   * We therefore keep forced authentication ON (secure local bind) and
  #     mint a scanner token once at provision time (sonarqube-provision).
  #     Anonymous users can't even browse, but that's fine: local scans use
  #     the cached token via home-modules/sonar.nix.
  virtualisation.oci-containers = {
    backend = "docker";

    containers = {
      sonar-postgres = {
        image = "postgres:16-alpine";
        autoStart = false;
        networks = [ "sonar-net" ];
        environmentFiles = [ envFile ];
        environment = {
          POSTGRES_USER = "sonarqube";
          POSTGRES_DB = "sonarqube";
        };
        # Named volume - data survives container recreation; no host UID clash.
        volumes = [ "sonar-pgdata:/var/lib/postgresql/data" ];
      };

      sonarqube = {
        image = "sonarqube:lts-community";
        autoStart = false;
        dependsOn = [ "sonar-postgres" ];
        networks = [ "sonar-net" ];
        environmentFiles = [ envFile ];
        environment = {
          SONAR_JDBC_URL = "jdbc:postgresql://sonar-postgres:5432/sonarqube";
          SONAR_JDBC_USERNAME = "sonarqube";
          # NO SONAR_FORCEAUTHENTICATION here - it doesn't apply (see comment
          # above) and forcing auth is what keeps the local bind safe. Scans
          # authenticate with the provisioned token instead.
        };
        volumes = [
          "${dataDir}/data:/opt/sonarqube/data"
          "${dataDir}/logs:/opt/sonarqube/logs"
          "${dataDir}/extensions:/opt/sonarqube/extensions"
        ];
        # localhost-only bind - not exposed on the LAN.
        ports = [ "127.0.0.1:9000:9000" ];
      };
    };
  };

  # Private docker bridge so `sonarqube` can resolve `sonar-postgres` by name.
  systemd.services.sonarqube-network = {
    description = "SonarQube docker bridge network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${dockerPkg}/bin/docker network inspect sonar-net >/dev/null 2>&1 || \
        ${dockerPkg}/bin/docker network create sonar-net
    '';
  };

  # Data dirs owned by the image's non-root uid 1000 + the one-time generated
  # DB password (never part of the Nix closure or secrets.nix).
  systemd.services.sonarqube-preflight = {
    description = "SonarQube data dirs and DB secret";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -o 1000 -g 1000 ${dataDir}/data ${dataDir}/logs ${dataDir}/extensions
      if [ ! -f ${envFile} ]; then
        pass=$(${pkgs.openssl}/bin/openssl rand -hex 16)
        umask 077
        printf 'POSTGRES_PASSWORD=%s\nSONAR_JDBC_PASSWORD=%s\n' "$pass" "$pass" > ${envFile}
      fi
    '';
  };

  # First-start bootstrap: create a scanner token once the web UI is up and
  # cache it in ${tokenFile}. This is the token source of truth for local
  # `sonar-scanner` runs (see home-modules/sonar.nix). Idempotent: re-run of
  # the module / container restart does not regenerate an existing token.
  systemd.services.sonarqube-provision = {
    description = "SonarQube scanner token provisioning";
    # Triggered by docker-sonarqube (it `wants` us). Order after both the app
    # and postgres containers so the web API is reachable when we run.
    after = [ "docker-sonarqube.service" "docker-sonar-postgres.service" ];
    path = [ pkgs.curl pkgs.python3 pkgs.gnugrep pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -e
      [ -s ${tokenFile} ] && exit 0
      # Wait for the SonarQube web UI (JVM boot takes 30-60s).
      for i in $(seq 1 60); do
        if curl -fsS -m 2 http://localhost:9000/api/system/status | grep -q '"status":"UP"'; then break; fi
        [ "$i" = 60 ] && { echo "SonarQube not ready after 60 attempts" >&2; exit 1; }
        sleep 2
      done
      # Local-only server: mint the scanner token with the bootstrap admin.
      # (Change the admin password via the UI/API first if you harden this.)
      TOKEN=$(curl -fsS -u admin:admin -X POST \
        "http://localhost:9000/api/user_tokens/generate" \
        --data-urlencode "login=admin" \
        --data-urlencode "name=sonar-scanner" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
      umask 022
      printf '%s\n' "$TOKEN" > ${tokenFile}
    '';
  };

  # The oci-containers module emits docker-sonarqube.service /
  # docker-sonar-postgres.service. Pull the docker daemon up on demand and
  # gate both on the network + preflight oneshots; then provision the token.
  systemd.services.docker-sonarqube = {
    wants = [ "docker.service" "sonarqube-provision.service" ];
    requires = [ "sonarqube-network.service" "sonarqube-preflight.service" ];
    after = [ "sonarqube-network.service" "sonarqube-preflight.service" "docker.service" ];
  };

  systemd.services.docker-sonar-postgres = {
    wants = [ "docker.service" ];
    requires = [ "sonarqube-network.service" "sonarqube-preflight.service" ];
    after = [ "sonarqube-network.service" "sonarqube-preflight.service" "docker.service" ];
  };
}