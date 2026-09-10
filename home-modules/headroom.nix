{
  pkgs,
  inputs,
  config,
  ...
}:
let
  # headroom-ai built from its own uv.lock via uv2nix (see nix/headroom.nix).
  # NOT added to home.packages — the venv's bin/python3 would collide with
  # other python environments in the profile; link only the CLI instead.
  headroom = import ../nix/headroom.nix { inherit pkgs inputs; };
  headroomProxyPort = 8787;
in
{
  # CLI entry on PATH (proxy runs via systemd with the absolute store path).
  home.file.".local/bin/headroom".source = headroom.binHeadroom;

  # ~/.local/bin is not in PATH anywhere in this config (checked); put it
  # there for the headroom CLI (rclone link there predates this, used by
  # flatpak via absolute path so it doesn't care).
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # Transparent transport plugin for opencode — auto-loaded from
  # ~/.config/opencode/plugins/*.js without any opencode.json edit.
  # Routes ALL providers (tw-bifrost, personal-openrouter, ...) through the
  # local headroom proxy by tagging the real upstream per request.
  home.file.".config/opencode/plugins/headroom-entry.js".source = headroom.opencodePlugin;

  # The plugin self-configures from this URL.
  home.sessionVariables.HEADROOM_PROXY_URL = "http://127.0.0.1:${toString headroomProxyPort}";

  # Local token-compression proxy for all opencode LLM traffic.
  # No upstream credentials involved — opencode's own auth.json and provider
  # headers flow through per-request; the proxy is a loopback MITM you own.
  systemd.user.services.headroom = {
    Unit = {
      Description = "Headroom token-compression proxy for AI coding agents";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${headroom}/bin/headroom proxy --port ${toString headroomProxyPort}";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "HOME=%h"
        "HEADROOM_BASE_URL=http://127.0.0.1:${toString headroomProxyPort}"
      ];
      MemoryMax = "4G";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
