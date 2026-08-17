{ pkgs, lib, secrets, ... }:
let
  redis = secrets.server.redis or { enable = false; };
  boot = redis.enable or false;
in
{
  # Always register the instance so it can be started manually (or via the
  # Noctalia toggle) even when auto-start is disabled. The `enable` secret only
  # controls whether it boots at start.
  services.redis.servers."".enable = true;
  services.redis.servers."".port = redis.port or 6379;
  services.redis.servers."".requirePass = redis.password or null;
  services.redis.servers."".user = redis.user or "redis";

  systemd.services.redis.wantedBy = lib.mkForce (if boot then [ "multi-user.target" ] else [ ]);
}