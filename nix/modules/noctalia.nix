{ pkgs, inputs, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  # install package
  environment.systemPackages = with pkgs; [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    cliphist
    wl-clipboard
    # ... maybe other stuff
  ];

  services.noctalia-shell.enable = true;
}
