{ pkgs, inputs, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  # install package
  environment.systemPackages = with pkgs; [
    inputs.noctalia.packages.${system}.default
    # ... maybe other stuff
  ];

  services.noctalia-shell.enable = true;
}
