{ pkgs, ... }:
{
  home.packages = with pkgs; [
    oci-cli
  ];
}
