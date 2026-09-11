# OTel dev observability stack — all Home Manager user services.
#
# Five independent systemd --user units, each individually start/stoppable
# from the gery/services Noctalia hub (passwordless — user units need no
# polkit). Always registered; the plugin's `otel_auto_start` setting (a
# plugin.toml default, GUI-editable) feeds the plugin's one-shot auto-start
# of the otel-stack.target at shell boot.
#
#   tempo   — traces   (query :3200, internal OTLP :14317/:14318)
#   mimir   — metrics  (:9009)
#   loki    — logs     (:3100)
#   otelcol — collector (receives apps on :4317 gRPC / :4318 HTTP)
#   grafana — UI       (:3000)
#
# NixOS has no HM modules for these, so the units are hand-written and the
# configs generated from Nix attrsets. State lives under ~/.local/state/otel/
# so data survives rebuilds and stays inside the home dir.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Ports (ints for configs, strings for URL interpolation). Tunable in
  # home-modules/otel.nix only — not a plugin setting (fixed listeners).
  grafanaPort = 3000;
  tempoPort = 3200;
  mimirPort = 9009;
  lokiPort = 3100;
  otlpGrpcPort = 4317;
  otlpHttpPort = 4318;

  # Tempo's internal OTLP receiver ports — offset from 4317/4318 so the
  # collector owns the well-known OTLP ports. Fixed (internal plumbing).
  tempoOtlpGrpc = "14317";
  tempoOtlpHttp = "14318";

  homeDir = config.home.homeDirectory;
  stateDir = "${homeDir}/.local/state/otel";
  cfgDir = "${config.xdg.configHome}/otel";

  yaml = pkgs.formats.yaml { };
  json = pkgs.formats.json { };
  ini = pkgs.formats.ini { };

  mkdirDirs = dirs: "${pkgs.coreutils}/bin/mkdir -p ${lib.concatStringsSep " " dirs}";

  tempoConfig = yaml.generate "tempo-config.yaml" {
    server = {
      http_listen_port = tempoPort;
      # Mimir's gRPC default (9095) collides with Tempo's own internal gRPC
      # server; Loki is moved to 9096, Tempo to 9097.
      grpc_listen_port = 9097;
    };
    usage_report.reporting_enabled = false;
    distributor.receivers.otlp.protocols = {
      grpc.endpoint = "127.0.0.1:${tempoOtlpGrpc}";
      http.endpoint = "127.0.0.1:${tempoOtlpHttp}";
    };
    storage.trace = {
      backend = "local";
      local.path = "${stateDir}/tempo/blocks";
      wal.path = "${stateDir}/tempo/wal";
    };
    # Tempo 3.x runtime defaults all live under /var/tempo (root-owned) —
    # redirect every one of them into the state dir.
    block_builder.wal.path = "${stateDir}/tempo/block-builder/traces";
    live_store = {
      shutdown_marker_dir = "${stateDir}/tempo/live-store/shutdown-marker";
      wal.path = "${stateDir}/tempo/live-store/traces";
    };
    backend_scheduler.local_work_path = "${stateDir}/tempo/work";
  };

  mimirConfig = yaml.generate "mimir-config.yaml" {
    multitenancy_enabled = false;
    server.http_listen_port = mimirPort;
    # Single-node: default ingester replication_factor is 3, which makes every
    # query fail with "too many unhealthy instances in the ring".
    ingester.ring.replication_factor = 1;
    blocks_storage = {
      backend = "filesystem";
      bucket_store.sync_dir = "${stateDir}/mimir/tsdb-sync";
      filesystem.dir = "${stateDir}/mimir/blocks";
      tsdb.dir = "${stateDir}/mimir/tsdb";
    };
  };

  # JSON is valid YAML for Loki; formats.json keeps the `from` date safely
  # quoted (same approach as the NixOS loki module).
  lokiConfig = json.generate "loki-config.json" {
    auth_enabled = false;
    server = {
      http_listen_port = lokiPort;
      # Mimir's gRPC server takes Loki's default 9095 — move Loki's.
      grpc_listen_port = 9096;
    };
    common = {
      path_prefix = "${stateDir}/loki";
      storage.filesystem = {
        chunks_directory = "${stateDir}/loki/chunks";
        rules_directory = "${stateDir}/loki/rules";
      };
      replication_factor = 1;
      ring.kvstore.store = "inmemory";
    };
    schema_config.configs = [
      {
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }
    ];
  };

  collectorConfig = yaml.generate "otel-collector-config.yaml" {
    receivers.otlp.protocols = {
      grpc.endpoint = "127.0.0.1:${toString otlpGrpcPort}";
      http.endpoint = "127.0.0.1:${toString otlpHttpPort}";
    };
    processors.batch = { };
    exporters = {
      "otlp/tempo" = {
        endpoint = "127.0.0.1:${tempoOtlpGrpc}";
        tls.insecure = true;
      };
      # The otlphttp exporter appends /v1/metrics and /v1/logs, and Mimir's
      # and Loki's native OTLP endpoints live at /otlp/v1/... — hence /otlp.
      "otlphttp/mimir" = {
        endpoint = "http://127.0.0.1:${toString mimirPort}/otlp";
        tls.insecure = true;
      };
      "otlphttp/loki" = {
        endpoint = "http://127.0.0.1:${toString lokiPort}/otlp";
        tls.insecure = true;
      };
    };
    extensions.health_check.endpoint = "127.0.0.1:13133";
    service = {
      extensions = [ "health_check" ];
      pipelines = {
        traces = {
          receivers = [ "otlp" ];
          processors = [ "batch" ];
          exporters = [ "otlp/tempo" ];
        };
        metrics = {
          receivers = [ "otlp" ];
          processors = [ "batch" ];
          exporters = [ "otlphttp/mimir" ];
        };
        logs = {
          receivers = [ "otlp" ];
          processors = [ "batch" ];
          exporters = [ "otlphttp/loki" ];
        };
      };
    };
  };

  grafanaIni = ini.generate "grafana.ini" {
    server = {
      http_addr = "127.0.0.1";
      http_port = grafanaPort;
    };
    paths = {
      data = "${stateDir}/grafana/data";
      logs = "${stateDir}/grafana/logs";
      plugins = "${stateDir}/grafana/plugins";
      provisioning = "${cfgDir}/grafana/provisioning";
    };
    analytics.reporting_enabled = false;
  };

  grafanaDatasources = yaml.generate "datasources.yaml" {
    apiVersion = 1;
    datasources = [
      {
        name = "Tempo";
        uid = "tempo";
        type = "tempo";
        url = "http://127.0.0.1:${toString tempoPort}";
        editable = false;
      }
      {
        name = "Mimir";
        uid = "mimir";
        type = "prometheus";
        url = "http://127.0.0.1:${toString mimirPort}/prometheus";
        isDefault = true;
        editable = false;
      }
      {
        name = "Loki";
        uid = "loki";
        type = "loki";
        url = "http://127.0.0.1:${toString lokiPort}";
        editable = false;
      }
    ];
  };
in
{
  xdg.configFile."otel/grafana/provisioning/datasources/datasources.yaml".source =
    grafanaDatasources;

  # systemd chdirs to WorkingDirectory before ExecStartPre runs, so the state
  # tree must exist before any unit can start — create it at HM activation.
  home.activation.createOtelStateDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p \
      ${stateDir}/tempo/blocks ${stateDir}/tempo/wal \
      ${stateDir}/tempo/block-builder/traces \
      ${stateDir}/tempo/live-store/shutdown-marker ${stateDir}/tempo/live-store/traces \
      ${stateDir}/tempo/work \
      ${stateDir}/mimir/blocks ${stateDir}/mimir/tsdb ${stateDir}/mimir/tsdb-sync ${stateDir}/mimir/data \
      ${stateDir}/loki/chunks ${stateDir}/loki/rules \
      ${stateDir}/otelcol \
      ${stateDir}/grafana/data ${stateDir}/grafana/logs ${stateDir}/grafana/plugins
  '';

  home.packages = [
    pkgs.tempo
    pkgs.mimir
    pkgs.grafana-loki
    pkgs.grafana
    pkgs.opentelemetry-collector-contrib
  ];

  systemd.user.services.tempo = {
    Unit = {
      Description = "Grafana Tempo (traces)";
      PartOf = [ "otel-stack.target" ];
    };
    Service = {
      ExecStartPre = mkdirDirs [
        "${stateDir}/tempo/blocks"
        "${stateDir}/tempo/wal"
        "${stateDir}/tempo/block-builder/traces"
        "${stateDir}/tempo/live-store/shutdown-marker"
        "${stateDir}/tempo/live-store/traces"
        "${stateDir}/tempo/work"
      ];
      ExecStart = "${pkgs.tempo}/bin/tempo --config.file=${tempoConfig}";
      WorkingDirectory = "${stateDir}/tempo";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.mimir = {
    Unit = {
      Description = "Grafana Mimir (metrics)";
      PartOf = [ "otel-stack.target" ];
    };
    Service = {
      ExecStartPre = mkdirDirs [
        "${stateDir}/mimir/blocks"
        "${stateDir}/mimir/tsdb"
        "${stateDir}/mimir/tsdb-sync"
        "${stateDir}/mimir/data"
      ];
      ExecStart = "${pkgs.mimir}/bin/mimir --config.file=${mimirConfig}";
      WorkingDirectory = "${stateDir}/mimir";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.loki = {
    Unit = {
      Description = "Grafana Loki (logs)";
      PartOf = [ "otel-stack.target" ];
    };
    Service = {
      ExecStartPre = mkdirDirs [
        "${stateDir}/loki/chunks"
        "${stateDir}/loki/rules"
      ];
      ExecStart = "${pkgs.grafana-loki}/bin/loki --config.file=${lokiConfig}";
      WorkingDirectory = "${stateDir}/loki";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.otel-collector = {
    Unit = {
      Description = "OpenTelemetry Collector";
      PartOf = [ "otel-stack.target" ];
      # Ordering only — no Wants, so the collector runs standalone and its
      # exporters retry until the backends are up.
      After = [
        "tempo.service"
        "mimir.service"
        "loki.service"
      ];
    };
    Service = {
      ExecStartPre = mkdirDirs [ "${stateDir}/otelcol" ];
      ExecStart = "${pkgs.opentelemetry-collector-contrib}/bin/otelcol-contrib --config=${collectorConfig}";
      WorkingDirectory = "${stateDir}/otelcol";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.grafana = {
    Unit = {
      Description = "Grafana (dashboards)";
      PartOf = [ "otel-stack.target" ];
    };
    Service = {
      ExecStartPre = mkdirDirs [
        "${stateDir}/grafana/data"
        "${stateDir}/grafana/logs"
        "${stateDir}/grafana/plugins"
      ];
      ExecStart = "${pkgs.grafana}/bin/grafana server --homepath ${pkgs.grafana}/share/grafana --config ${grafanaIni}";
      WorkingDirectory = "${stateDir}/grafana";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Single logical unit for the services hub: starting it pulls in all five,
  # stopping it tears them all down (PartOf on each service). No WantedBy —
  # boot auto-start is the plugin's otel_auto_start one-shot.
  systemd.user.targets.otel-stack = {
    Unit = {
      Description = "OpenTelemetry dev stack (tempo/mimir/loki/collector/grafana)";
      Wants = [
        "tempo.service"
        "mimir.service"
        "loki.service"
        "otel-collector.service"
        "grafana.service"
      ];
      After = [
        "tempo.service"
        "mimir.service"
        "loki.service"
        "otel-collector.service"
        "grafana.service"
      ];
    };
  };
}
