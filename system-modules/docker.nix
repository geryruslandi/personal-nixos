{ pkgs, lib, secrets, ... }:
let
  docker = secrets.server.docker or { enable = false; };
  boot = docker.enable or false;
in
{
  virtualisation = {
    docker = {
      # Always registered so the daemon/socket/group exist — `enable` only
      # controls auto-start at boot (`enableOnBoot`).
      enable = true;
      enableOnBoot = boot;
      autoPrune.enable = boot;
    };

    containers = {
      enable = true;
      registries.settings.registries.search.registries = [
        "docker.io"
        "registry.fedoraproject.org"
      ];
    };
  };

  # Socket activation would otherwise boot dockerd on first client connect even
  # when auto-start is off.
  systemd.sockets.docker.wantedBy = lib.mkForce (if boot then [ "sockets.target" ] else [ ]);

  environment.systemPackages = with pkgs; [
    docker-compose

    kubectl
    k3d
    just
  ];

  users.users.geryruslandi.extraGroups = [ "docker" ];
}