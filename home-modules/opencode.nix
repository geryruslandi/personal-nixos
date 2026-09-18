{ pkgs, lib, inputs, ... }:
{
  # OpenCode always comes from the fork's own flake (see the `opencode` input
  # in flake.nix), not nixpkgs.
  home.packages = with pkgs; [
    rtk
    inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.activation.setupOpenCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rtk}/bin/rtk init -g --opencode --auto-patch
  '';
}
