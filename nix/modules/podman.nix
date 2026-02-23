{ pkgs, ... }:

{
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # This is the correct path for registry settings
    containers = {
      enable = true;
      registries.search = [
        "docker.io"
        "registry.fedoraproject.org"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    podman-compose
    podman-desktop

    # Kubernetes client
    kubectl
    k3d
    just
  ];
}
