# Docker — ROOTFUL, system-level daemon owned by the services hub plugin.
#
# The daemon is the nixpkgs system unit docker.service, socket at
# /run/docker.sock (root:docker, 0660), data in /var/lib/docker. Its full
# lifecycle belongs to the services hub plugin: toggle via the panel, auto-
# start via the plugin's docker_auto_start one-shot at shell boot — NOT at
# boot (enableOnBoot = false keeps it out of multi-user.target). The socket is
# NOT started at boot either: while it listens, any client (e.g. the
# mini-docker bar widget polling `docker ps`) would socket-activate the daemon
# right after the hub stopped it. Starting docker.service from the hub pulls
# the socket in via Requires=docker.socket, and the hub's stop also stops it.

#
# Consequences of rootful:
#   * daemon + images/volumes run as root in /var/lib/docker (migrated from the
#     old rootless ~/.local/share/docker),
#   * the user is in the "docker" group and talks to the default
#     /run/docker.sock (no DOCKER_HOST needed),
#   * works with k3d/kubectl; all ports available,
#   * SonarQube (home-modules/sonarqube.nix) runs on this daemon.
{ lib, pkgs, ... }:
{
  virtualisation = {
    docker = {
      enable = true;
      # Keep the daemon out of boot: the plugin owns start/stop.
      enableOnBoot = false;
    };

    containers = {
      enable = true;
      registries.settings.registries.search.registries = [
        "docker.io"
        "registry.fedoraproject.org"
      ];
    };
  };

  # Never arm socket activation at boot. docker.service Requires=docker.socket,
  # so a hub start still brings the socket up; stopping the daemon from the hub
  # stops the socket too (see gery/services stopService).
  systemd.sockets.docker.wantedBy = lib.mkForce [ ];

  environment.systemPackages = with pkgs; [
    docker-compose

    # Local k8s tooling (k3d/k3s). helm + kustomize are required by the
    # backend's `just run` recipes (manifest rendering, Envoy Gateway install).
    kubectl
    k3d
    just
    kubernetes-helm
    kustomize
    postgresql
  ];
}
