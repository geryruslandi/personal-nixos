{
  inputs,
  pkgs,
  secrets,
  ...
}:
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  services.displayManager.noctalia-greeter = {
    enable = true;
    # Wallpaper/palette sync from the Noctalia shell without a polkit prompt
    passwordless-sync-users = [ secrets.username ];
    settings = {
      session.default = "Hyprland";
      user.default = secrets.username;
      cursor = {
        theme = "Bibata-Modern-Classic";
        path = "${pkgs.bibata-cursors}/share/icons";
        size = 24;
      };
      keyboard.layout = "us";
    };
  };
}
