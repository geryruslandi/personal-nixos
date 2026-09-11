# Dev-server wrappers for the gery/services Noctalia hub plugin.
#
# After the secrets.server removal, redis/postgres/mysql/seaweedfs are no
# longer NixOS system services. Their full lifecycle is owned by the plugin:
# it builds a start command line out of its GUI settings (ports, password,
# datadir, bind IP, databases) and runs it as a transient systemd --user unit
# (`systemd-run --user --unit=... --collect`), exactly like seanime/mailpit.
#
# These wrappers are the "tool side" of that contract: idempotent provisioning
# (initdb / install-db when the datadir is empty) executed at START time
# instead of Nix evaluation time — which is precisely why ports/passwords/
# databases can live in plugin settings. Every wrapper:
#   * provisions state under ~/.local/state/<name>-dev on first start,
#   * applies CLI-provided credentials/databases on every start,
#   * leaves the daemon(s) running in the foreground (Restart=on-failure
#     re-provisions idempotently on a crash restart).
# Stopping the transient unit kills the whole cgroup — including any child
# process a wrapper spawned — so nothing leaks after a panel toggle-off.
#
# Credentials apply cleanly on a FRESH datadir; changing the password/user on
# an already-provisioned datadir requires wiping it first (the client that
# applies the change authenticates with the OLD credentials, which the plugin
# no longer knows).
{
  pkgs,
  ...
}:
let
  scriptDir = "gery-dev-scripts";
in
{
  home.packages = with pkgs; [
    redis
    postgresql
    mariadb
    seaweedfs
  ];

  # Redis ---------------------------------------------------------------------

  xdg.configFile."${scriptDir}/gery-redis-dev" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Dev redis server under the user account.
      #   gery-redis-dev [--port N] [--password P] [--dir PATH]
      set -eu
      usage() { echo "usage: gery-redis-dev [--port N] [--password P] [--dir PATH]" >&2; exit 1; }

      dir="" port="6379" password=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --dir) dir="$2"; shift 2 ;;
          --port) port="$2"; shift 2 ;;
          --password) password="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$dir" ] || dir="''${XDG_STATE_HOME:-$HOME/.local/state}/redis-dev"
      mkdir -p "$dir"

      # Persistence off: dev cache semantics (throwaway data).
      set -- --port "$port" --dir "$dir" --save "" --appendonly no
      if [ -n "$password" ]; then
        set -- "$@" --requirepass "$password"
      fi
      exec "${pkgs.redis}/bin/redis-server" "$@"
    '';
  };

  # Postgres ------------------------------------------------------------------

  xdg.configFile."${scriptDir}/gery-pg-dev" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Provision-on-start Postgres user service for the services hub plugin.
      #   gery-pg-dev --port N [--password P] [--user U] [--databases "db1 db2 ..."]
      # Local (TCP 127.0.0.1) connections are trusted by the initdb-generated
      # pg_hba; the password exists for GUI clients that insist on one.
      set -eu
      usage() { echo "usage: gery-pg-dev --port N [--password P] [--user U] [--databases LIST]" >&2; exit 1; }

      port="" password="" user="postgres" databases=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --port) port="$2"; shift 2 ;;
          --password) password="$2"; shift 2 ;;
          --user) user="$2"; shift 2 ;;
          --databases) databases="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$port" ] || { echo "gery-pg-dev: --port required" >&2; exit 1; }
      case "''${user:-x}" in *[!a-zA-Z0-9_-]*) echo "gery-pg-dev: invalid user" >&2; exit 1 ;; esac
      case "$databases" in *[!a-zA-Z0-9_-]*) echo "gery-pg-dev: invalid database name" >&2; exit 1 ;; esac

      stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/postgres-dev"
      mkdir -p "$stateDir"
      sockDir="$stateDir/sock"
      mkdir -p "$sockDir"
      # The socket dir must be 0700 (postgres refuses otherwise); keep the
      # ~/.local/state parent permissions untouched.
      chmod 700 "$sockDir"

      PGDATA="$stateDir/data"
      if [ ! -s "$PGDATA/PG_VERSION" ]; then
        "${pkgs.postgresql}/bin/initdb" -D "$PGDATA" \
          --auth-local=trust --auth-host=trust -U "$user" >/dev/null
      fi

      # Daemon in the background of this wrapper so provisioning can run right
      # after startup; if postgres dies, wait fails and systemd restarts the
      # transient unit (Restart=on-failure), re-provisioning idempotently.
      "${pkgs.postgresql}/bin/postgres" -D "$PGDATA" \
        -c "port=$port" -c "listen_addresses=127.0.0.1" \
        -c "unix_socket_directories=$sockDir" &
      pgpid=$!

      i=0
      until "${pkgs.postgresql}/bin/pg_isready" -h "127.0.0.1" -p "$port" -q; do
        i=$((i + 1))
        if [ "$i" -ge 60 ]; then
          echo "gery-pg-dev: postgres did not become ready in 60s" >&2
          exit 1
        fi
        sleep 1
      done

      pgsql() { "${pkgs.postgresql}/bin/psql" -h "127.0.0.1" -p "$port" -U "$user" -d postgres "$@"; }
      if [ -n "$password" ]; then
        safePass="''${password//\'/\'\'}"
        pgsql -q -c "ALTER ROLE \"$user\" WITH PASSWORD '$safePass';" || true
      fi
      for db in $databases; do
        "${pkgs.postgresql}/bin/createdb" -h "127.0.0.1" -p "$port" -U "$user" "$db" >/dev/null 2>&1 || true
      done

      wait "$pgpid"
    '';
  };

  # MariaDB -------------------------------------------------------------------

  xdg.configFile."${scriptDir}/gery-mysql-dev" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Provision-on-start MariaDB user service for the services hub plugin.
      #   gery-mysql-dev --port N [--password P] [--user U] [--databases "db1 db2 ..."]
      set -eu
      usage() { echo "usage: gery-mysql-dev --port N [--password P] [--user U] [--databases LIST]" >&2; exit 1; }

      port="" password="" user="root" databases=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --port) port="$2"; shift 2 ;;
          --password) password="$2"; shift 2 ;;
          --user) user="$2"; shift 2 ;;
          --databases) databases="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$port" ] || { echo "gery-mysql-dev: --port required" >&2; exit 1; }
      case "''${user:-x}" in *[!a-zA-Z0-9_-]*) echo "gery-mysql-dev: invalid user" >&2; exit 1 ;; esac
      case "$databases" in *[!a-zA-Z0-9_-]*) echo "gery-mysql-dev: invalid database name" >&2; exit 1 ;; esac

      stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/mysql-dev"
      datadir="$stateDir/data"
      socket="$stateDir/mysqld.sock"
      mkdir -p "$datadir"

      if [ ! -d "$datadir/mysql" ]; then
        "${pkgs.mariadb}/bin/mariadb-install-db" \
          --auth-root-authentication-method=normal \
          --datadir="$datadir" \
          --skip-test-db >/dev/null
      fi

      "${pkgs.mariadb}/bin/mariadbd" --datadir="$datadir" --socket="$socket" \
        --port="$port" --bind-address=127.0.0.1 &
      mypid=$!
      trap 'kill "$mypid" 2>/dev/null || true; wait "$mypid" 2>/dev/null || true' TERM INT EXIT

      # Readiness: a failed ping with "Access denied" still means the server
      # is UP (the root password just doesn't match this run's --password);
      # only the timeout means actually not ready.
      i=0
      while :; do
        out=$( ("${pkgs.mariadb}/bin/mysqladmin" -u root -S "$socket" ping) 2>&1 || true)
        case "$out" in
          *"mysqld is alive"*|*"Access denied"*) break ;;
        esac
        i=$((i + 1))
        if [ "$i" -ge 60 ]; then
          echo "gery-mysql-dev: mariadb did not become ready in 60s" >&2
          exit 1
        fi
        sleep 1
      done

      # Client: no-password first (fresh datadir has an empty root
      # password); fall back to the desired password (datadirs provisioned
      # in a previous run, where the setting matches).
      msql() {
        if "${pkgs.mariadb}/bin/mysql" -u root -S "$socket" -e "$1" >/dev/null 2>&1; then
          return 0
        fi
        if [ -n "$password" ]; then
          "${pkgs.mariadb}/bin/mysql" -u root -S "$socket" --password="$password" -e "$1" >/dev/null 2>&1 || true
        fi
      }
      if [ "$user" != "root" ]; then
        msql "CREATE USER IF NOT EXISTS '$user'@'localhost';"
      fi
      if [ -n "$password" ]; then
        msql "ALTER USER IF EXISTS '$user'@'localhost' IDENTIFIED BY '$password';"
      fi
      for db in $databases; do
        msql "CREATE DATABASE IF NOT EXISTS \`$db\`;"
      done

      wait "$mypid"
    '';
  };

  # SeaweedFS ------------------------------------------------------------------

  xdg.configFile."${scriptDir}/gery-seaweed-dev" = {
    executable = true;
    text = ''
      #!/bin/sh
      # SeaweedFS cluster (master + volume + filer) as one process group under
      # the services hub plugin's transient user unit.
      #   gery-seaweed-dev [--datadir PATH] [--bind-ip IP] \
      #                    [--master-port N] [--volume-port N] [--filer-port N]
      set -u
      usage() { echo "usage: gery-seaweed-dev [--datadir P] [--bind-ip IP] [--master-port N] [--volume-port N] [--filer-port N]" >&2; exit 1; }

      datadir="" bindIp="127.0.0.1" masterPort="9333" volumePort="8080" filerPort="8888"
      while [ $# -gt 0 ]; do
        case "$1" in
          --datadir) datadir="$2"; shift 2 ;;
          --bind-ip) bindIp="$2"; shift 2 ;;
          --master-port) masterPort="$2"; shift 2 ;;
          --volume-port) volumePort="$2"; shift 2 ;;
          --filer-port) filerPort="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -n "$datadir" ] || datadir="''${XDG_STATE_HOME:-$HOME/.local/state}/seaweedfs"

      mkdir -p "$datadir/master" "$datadir/volume" "$datadir/filer"

      weed="${pkgs.seaweedfs}/bin/weed"

      "$weed" master -ip "$bindIp" -port "$masterPort" -mdir "$datadir/master" &
      master=$!
      sleep 2
      "$weed" volume -port "$volumePort" -ip "$bindIp" \
        -dir "$datadir/volume" -master "$bindIp:$masterPort" -disk ssd &
      volume=$!
      "$weed" filer -port "$filerPort" -master "$bindIp:$masterPort" \
        -defaultStoreDir "$datadir/filer" &
      filer=$!

      # If ANY member exits, stop the whole group so systemd restarts a
      # coherent cluster. (wait -n needs bash; NixOS /bin/sh is bash.)
      rc=0
      wait -n "$master" "$volume" "$filer" || rc=$?
      kill "$master" "$volume" "$filer" 2>/dev/null || true
      exit "$rc"
    '';
  };
}
