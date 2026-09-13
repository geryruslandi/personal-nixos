{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  programs.noctalia-greeter = {
    enable = true;
    # Wallpaper/palette sync from the Noctalia shell without a polkit prompt
    passwordless-sync-users = [ "geryruslandi" ];
    settings = {
      session.default = "Hyprland";
      user.default = "geryruslandi";
      cursor = {
        theme = "Bibata-Modern-Classic";
        path = "${pkgs.bibata-cursors}/share/icons";
        size = 24;
      };
      keyboard.layout = "us";
    };
  };
}
