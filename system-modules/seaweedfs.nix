{ pkgs, lib, secrets, ... }:
let
  sf = secrets.server.seaweedfs or { enable = false; };
  enabled = sf.enable or false;

  masterPort = toString (sf.masterPort or 9333);
  volumePort = toString (sf.volumePort or 8080);
  filerPort = toString (sf.filerPort or 8888);
  dataDir = sf.dataDir or "/mnt/data-ssd/seaweedfs";
  # Address the cluster advertises/listens on. Defaults to localhost (single
  # machine); set to your LAN IP in secrets to expose it on the network.
  bindIp = sf.bindIp or "127.0.0.1";
  masterAddr = "${bindIp}:${masterPort}";
in
{
  users.users.seaweedfs = {
    isSystemUser = true;
    group = "seaweedfs";
    description = "SeaweedFS storage daemons";
  };
  users.groups.seaweedfs = { };

  # Make sure the data dirs exist and are owned by the seaweedfs user.
  # Always applied — the cluster can be started manually even when auto-start
  # is disabled, so the dirs must exist.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 seaweedfs seaweedfs - -"
    "d ${dataDir}/master 0755 seaweedfs seaweedfs - -"
    "d ${dataDir}/volume 0755 seaweedfs seaweedfs - -"
    "d ${dataDir}/filer 0755 seaweedfs seaweedfs - -"
  ];

  # Single logical unit — the Noctalia toggle starts/stops this target,
  # which pulls/tears down the whole cluster.
  systemd.targets.seaweedfs = {
    description = "SeaweedFS cluster";
    wants = [ "seaweedfs-master.service" "seaweedfs-volume.service" "seaweedfs-filer.service" ];
    after = [ "seaweedfs-master.service" "seaweedfs-volume.service" "seaweedfs-filer.service" ];
    wantedBy = lib.mkIf enabled [ "multi-user.target" ];
  };

  systemd.services.seaweedfs-master = {
    description = "SeaweedFS master";
    before = [ "seaweedfs-volume.service" "seaweedfs-filer.service" ];
    partOf = [ "seaweedfs.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.seaweedfs}/bin/weed master -ip ${bindIp} -port ${masterPort} -mdir ${dataDir}/master";
      Restart = "on-failure";
      RestartSec = 3;
      User = "seaweedfs";
      Group = "seaweedfs";
    };
  };

  systemd.services.seaweedfs-volume = {
    description = "SeaweedFS volume server";
    after = [ "network.target" "seaweedfs-master.service" ];
    requires = [ "seaweedfs-master.service" ];
    partOf = [ "seaweedfs.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.seaweedfs}/bin/weed volume -port ${volumePort} -ip ${bindIp} -dir ${dataDir}/volume -master ${masterAddr} -disk ssd";
      Restart = "on-failure";
      RestartSec = 3;
      User = "seaweedfs";
      Group = "seaweedfs";
    };
  };

  systemd.services.seaweedfs-filer = {
    description = "SeaweedFS filer";
    after = [ "network.target" "seaweedfs-master.service" ];
    requires = [ "seaweedfs-master.service" ];
    partOf = [ "seaweedfs.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.seaweedfs}/bin/weed filer -port ${filerPort} -dir ${dataDir}/filer -master ${masterAddr}";
      Restart = "on-failure";
      RestartSec = 3;
      User = "seaweedfs";
      Group = "seaweedfs";
    };
  };
}