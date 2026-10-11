{ pkgs, ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.geryruslandi = {
    isNormalUser = true;
    description = "Gery Ruslandi";
    extraGroups = [
      "networkmanager"
      "wheel"
      "battery_ctl"
      "docker"
    ];
    packages = with pkgs; [
      vscode
      nixfmt
      firefox
    ];
  };
}
