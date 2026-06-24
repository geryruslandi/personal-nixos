{
  pkgs,
  ...
}:
{
  services.mysql = {
    enable = true;
    package = pkgs.mysql84;
  };

  # TO handle some mysql client UI still using mariadb instead of mysql
  environment.systemPackages = with pkgs; [
    mariadb
  ];

}
