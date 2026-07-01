{ pkgs, lib, ... }:
{
  home.packages = [
    (pkgs.python3.withPackages (ps: with ps; [
      pip
      virtualenv
    ]))
  ];

  home.activation.createGlobalVenv = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/.virtualenvs/global" ]; then
      ${pkgs.python3}/bin/python -m venv "$HOME/.virtualenvs/global"
    fi
  '';

  programs.zsh.initExtra = ''
    source "$HOME/.virtualenvs/global/bin/activate"
  '';
}
