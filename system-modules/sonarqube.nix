{ config, pkgs, lib, ... }:
let
  dataDir = "/var/lib/sonarqube";
  envFile = "${dataDir}/.db.env";
  dockerPkg = config.virtualisation.docker.package;
in
{
  # Global SonarQube server (Community) as two OCI containers:
  #   sonar-postgres (postgres:16-alpine) backend + the sonarqube app itself.
  # Uses the docker backend - so both live on the shared docker.service; if
  # Docker is toggled off via the Services Hub, these go down with it.
  # autoStart = false -> registered but never boots; start/stop via the
  # Services Hub (passwordless, see polkit.nix) or `systemctl start
  # docker-sonarqube`.
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
          # Anonymous scan + browse (localhost-only bound server) - no tokens.
          SONAR_FORCEAUTHENTICATION = "false";
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

  # The oci-containers module emits docker-sonarqube.service /
  # docker-sonar-postgres.service. Pull the docker daemon up on demand and
  # gate both on the network + preflight oneshots.
  systemd.services.docker-sonarqube = {
    wants = [ "docker.service" ];
    requires = [ "sonarqube-network.service" "sonarqube-preflight.service" ];
    after = [ "sonarqube-network.service" "sonarqube-preflight.service" "docker.service" ];
  };

  systemd.services.docker-sonar-postgres = {
    wants = [ "docker.service" ];
    requires = [ "sonarqube-network.service" "sonarqube-preflight.service" ];
    after = [ "sonarqube-network.service" "sonarqube-preflight.service" "docker.service" ];
  };
}