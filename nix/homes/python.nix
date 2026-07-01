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
    export LD_LIBRARY_PATH="${lib.makeLibraryPath (with pkgs; [
      stdenv.cc.cc
      zlib
    ])}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    source "$HOME/.virtualenvs/global/bin/activate"
  '';
}
