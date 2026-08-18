{ pkgs, lib, ... }:
{
  home.packages = [
    (pkgs.python3.withPackages (ps: with ps; [
      pip
      virtualenv
    ]))
  ];

  home.activation.createGlobalVenv = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -x "$HOME/.virtualenvs/global/bin/python" ]; then
      rm -rf "$HOME/.virtualenvs/global"
      ${pkgs.python3}/bin/python -m venv "$HOME/.virtualenvs/global"
    fi
  '';

  programs.zsh.initContent = ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath (with pkgs; [
      gcc16.cc
      zlib
    ])}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    source "$HOME/.virtualenvs/global/bin/activate"
  '';
}
