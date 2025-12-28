{
  pkgs,
  config,
  ...
}:
{
  services.podman.enable = true;

  home.packages = with pkgs; [
    podman-compose
    # This creates a "fake" docker-compose that calls podman-compose
    (writeShellScriptBin "docker-compose" ''
      exec ${podman-compose}/bin/podman-compose "$@"
    '')
    # It's usually good to do the same for 'docker' if you haven't
    (writeShellScriptBin "docker" ''
      exec ${podman}/bin/podman "$@"
    '')
  ];
}
