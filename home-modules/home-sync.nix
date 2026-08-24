{
  config,
  lib,
  secrets,
  ...
}:
let
  # Real filesystem path to this repo's home-sync directory.
  #
  # These are OUT-OF-STORE symlinks: `~/.config/nvim` points directly at
  # `home-sync/.config/nvim` inside this repo, so editing a file through the
  # link edits the repo file itself and `git status` here detects the change.
  repoRoot = secrets.projectPath;
  homeSyncReal = "${repoRoot}/home-sync";

  # Nix path used for directory discovery (pure readDir of the flake source).
  homeSyncSrc = ../home-sync;

  mkLink = rel: lib.nameValuePair rel {
    source = config.lib.file.mkOutOfStoreSymlink "${homeSyncReal}/${rel}";
  };

  # Repo dirs that are MERGED into $HOME (each child linked individually)
  # instead of replacing $HOME/<dir> wholesale, because the real dirs hold
  # other state. `.config` is managed by Home Manager itself; `.local/share/
  # noctalia/plugins` is Noctalia's plugin dir (settings, plugin-cache, other
  # installed plugins live alongside it).
  mergeDirs = [
    ".config"
    ".local/share/noctalia/plugins"
  ];

  # True when a repo dir is a merge target itself or an ancestor of one.
  # Ancestors must also be merged (walked, not wholesale-linked) — otherwise
  # `$HOME/.local` would become a symlink to the repo and clobber state.
  isMergeAncestor = rel:
    builtins.elem rel mergeDirs
    || lib.any (m: lib.hasPrefix "${rel}/" m) mergeDirs;

  # Link one entry. Leaf entries (files, or dirs that aren't merge ancestors)
  # become a single out-of-store symlink; merge ancestors are walked so their
  # children are linked individually into the corresponding $HOME path.
  linkEntry = dir: name: type: let
    rel = if dir == "" then name else "${dir}/${name}";
  in
    if type == "directory" && isMergeAncestor rel then
      lib.mapAttrsToList (child: t: linkEntry rel child t)
        (builtins.readDir "${toString homeSyncSrc}/${rel}")
    else
      [ (mkLink rel) ];

  entries = lib.flatten (lib.mapAttrsToList (linkEntry "") (builtins.readDir homeSyncSrc));
in
{
  home.file = lib.listToAttrs entries;
}
