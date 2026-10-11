# Docker — ROOTFUL, system-level daemon owned by the services hub plugin.
#
# The daemon is the nixpkgs system unit docker.service, socket at
# /run/docker.sock (root:docker, 0660), data in /var/lib/docker. Its full
# lifecycle belongs to the services hub plugin: toggle via the panel, auto-
# start via the plugin's docker_auto_start one-shot at shell boot — NOT at
# boot (enableOnBoot = false keeps it out of multi-user.target). The socket
# stays active (sockets.target), so the daemon can still be socket-activated
# on the first client connect.
#
# Consequences of rootful:
#   * daemon + images/volumes run as root in /var/lib/docker (migrated from the
#     old rootless ~/.local/share/docker),
#   * the user is in the "docker" group and talks to the default
#     /run/docker.sock (no DOCKER_HOST needed),
#   * works with k3d/kubectl; all ports available,
#   * SonarQube (home-modules/sonarqube.nix) runs on this daemon.
{ pkgs, ... }:
{
  virtualisation = {
    docker = {
      enable = true;
      # Keep the daemon out of boot: the plugin owns start/stop. The socket
      # remains active, so the daemon can still be socket-activated on demand.
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
