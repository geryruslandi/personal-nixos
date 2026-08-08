{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    rtk
  ];

  home.sessionPath = [ "$HOME/.opencode/bin" ];

  home.activation.setupOpenCode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.opencode/bin/opencode" ]; then
      echo "Installing opencode..."
      ${pkgs.curl}/bin/curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
    fi
    ${pkgs.rtk}/bin/rtk init -g --opencode --auto-patch
  '';
}
