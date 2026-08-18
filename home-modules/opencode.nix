{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    opencode
    rtk
  ];

  home.activation.setupOpenCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rtk}/bin/rtk init -g --opencode --auto-patch
  '';
}
