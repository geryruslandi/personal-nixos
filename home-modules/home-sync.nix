{
  config,
  lib,
  ...
}:
let
  # Real filesystem path to this repo's home-sync directory.
  #
  # These are OUT-OF-STORE symlinks: `~/.config/nvim` points directly at
  # `home-sync/.config/nvim` inside this repo, so editing a file through the
  # link edits the repo file itself and `git status` here detects the change.
  repoRoot = "${config.home.homeDirectory}/Projects/personal-nixos";
  homeSyncReal = "${repoRoot}/home-sync";

  # Nix path used for directory discovery (pure readDir of the flake source).
  homeSyncSrc = ../home-sync;

  mkLink = rel: lib.nameValuePair rel {
    source = config.lib.file.mkOutOfStoreSymlink "${homeSyncReal}/${rel}";
  };

  # Link every top-level entry in home-sync. The `.config` directory is
  # special-cased: its children are linked individually so we don't replace
  # $HOME/.config wholesale (Home Manager also manages files there).
  entries =
    lib.flatten (
      lib.mapAttrsToList (name: _type:
        if name == ".config" then
          lib.mapAttrsToList (child: _: mkLink ".config/${child}")
            (builtins.readDir "${toString homeSyncSrc}/.config")
        else
          [ (mkLink name) ]
      ) (builtins.readDir homeSyncSrc)
    );
in
{
  home.file = lib.listToAttrs entries;
}
