{ pkgs, lib, secrets, ... }:
let
  redis = secrets.server.redis or { enable = false; };
in
{
  services.redis.servers."".enable = redis.enable or false;
  services.redis.servers."".port = redis.port or 6379;
  services.redis.servers."".requirePass = redis.password or null;
  services.redis.servers."".user = redis.user or "redis";
}
