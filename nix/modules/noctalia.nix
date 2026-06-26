{ pkgs, inputs, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  # install package
  environment.systemPackages = with pkgs; [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    cliphist
    wtype
    wl-clipboard
    # ... maybe other stuff
  ];

  # Systemd startup is deprecated for Noctalia.
  # Noctalia is now launched via Hyprland's exec-once instead.
  # services.noctalia-shell.enable = true;
}
