{ config, pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.geryruslandi = {
    isNormalUser = true;
    description = "Gery Ruslandi";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
      vscode
      nixfmt-rfc-style
      kdePackages.qtsvg
      firefox
      bitwarden-desktop
    ];
  };
}
