{ pkgs, ... }:

{
  virtualisation = {
    docker = {
      enable = true;
      autoPrune.enable = true;
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

    kubectl
    k3d
    just
  ];

  users.users.geryruslandi.extraGroups = [ "docker" ];
}
