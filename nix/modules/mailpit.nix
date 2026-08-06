{ pkgs, lib, secrets, ... }:
let
  mp = secrets.server.mailpit or { enable = false; };
in
{
  systemd.services.mailpit = {
    description = "Mailpit - email and SMTP testing tool";
    after = [ "network.target" ];
    wantedBy = lib.mkIf (mp.enable or false) [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.mailpit}/bin/mailpit --smtp 127.0.0.1:${toString (mp.smtpPort or 1025)} --listen 127.0.0.1:${toString (mp.uiPort or 8025)}";
      Restart = "on-failure";
      DynamicUser = true;
    };
  };
}
