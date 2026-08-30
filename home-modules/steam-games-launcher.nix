{
  pkgs,
  lib,
  ...
}:
let
  # Manifests that ship with Steam but must never become launcher entries:
  # Proton builds, Steam Linux Runtimes, Steamworks redistributables — plus
  # games that already register their own desktop entry (e.g. Wallpaper Engine).
  skipPattern = let
    runtimeTools = [
      "Proton .*"
      "Steam Linux Runtime.*"
      "Steam Runtime.*"
      "Steamworks Common Redistributables.*"
    ];
    hiddenGames = [
      "Wallpaper Engine"
    ];
  in
  "^(${lib.concatStringsSep "|" (runtimeTools ++ hiddenGames)})$";

  # Parses every Steam library's appmanifest_*.acf and (re)writes
  # ~/.local/share/applications/steam-game-<appid>.desktop entries so
  # all installed games show up in launchers (Vicinae, Noctalia, ...).
  # Library roots are read from libraryfolders.vdf at runtime, so games
  # on any mounted SteamLibrary are picked up.
  indexerScript = pkgs.writeShellScript "steam-game-index" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.curl pkgs.imagemagick ]}:$PATH"

    steamDir="$HOME/.local/share/Steam"
    appsDir="$HOME/.local/share/applications"
    libraryVdf="$steamDir/config/libraryfolders.vdf"
    iconCacheDir="$HOME/.local/share/steam-game-icons"
    declare -A seen=()

    mkdir -p "$appsDir" "$iconCacheDir"

    libraries=("$steamDir")
    while IFS= read -r lib; do
      [[ -d "$lib" && "$lib" != "$steamDir" ]] && libraries+=("$lib")
    done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]+"([^"]+)".*/\1/p' "$libraryVdf" 2>/dev/null)

    for lib in "''${libraries[@]}"; do
      steamapps="$lib/steamapps"
      [[ -d "$steamapps" ]] || continue
      for acf in "$steamapps"/appmanifest_*.acf; do
        [[ -e "$acf" ]] || continue
        appid="$(sed -nE 's/^[[:space:]]*"appid"[[:space:]]+"([0-9]+)".*/\1/p' "$acf" | head -n1)"
        name="$(sed -nE 's/^[[:space:]]*"name"[[:space:]]+"(.*)"[[:space:]]*$/\1/p' "$acf" | head -n1)"
        state="$(sed -nE 's/^[[:space:]]*"StateFlags"[[:space:]]+"([0-9]+)".*/\1/p' "$acf" | head -n1)"
        [[ -n "$appid" && -n "$name" && -n "$state" ]] || continue

        printf '%s' "$name" | grep -qE '${skipPattern}' && continue
        if (( (state & 4) == 0 )); then continue; fi

        # Icon resolution: Steam-exported hicolor icon > cached cover art
        # (downloaded from Steam's public CDN as portrait cover, fallback to
        # header) > generic steam logo. Converted to PNG so Icon= stays
        # spec-correct.
        icon="steam"
        iconfile="$(ls "$HOME/.local/share/icons/hicolor/"*"/apps/steam_icon_$appid.png" 2>/dev/null | head -n1 || true)"
        if [[ -n "$iconfile" ]]; then
          icon="steam_icon_$appid"
        elif [[ -f "$iconCacheDir/$appid.png" ]]; then
          icon="$iconCacheDir/$appid.png"
        else
          tmp="$(mktemp "$iconCacheDir/$appid.XXXXXX")"
          for art in library_600x900 header; do
            if curl -fsSL --max-time 15 -o "$tmp" "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid/$art.jpg" \
              && magick "$tmp" "$iconCacheDir/$appid.png"; then
              icon="$iconCacheDir/$appid.png"
              break
            fi
          done
          rm -f "$tmp"
        fi

        name="''${name//\"/}"
        entry="$appsDir/steam-game-$appid.desktop"
        cat > "$entry.tmp" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Play $name on Steam
Exec=steam steam://rungameid/$appid
Icon=$icon
Terminal=false
Categories=Game;
EOF
        mv "$entry.tmp" "$entry"
        seen["$appid"]=1
      done
    done

    # Drop entries and cached art for games that are no longer installed
    shopt -s nullglob
    for f in "$appsDir"/steam-game-*.desktop "$iconCacheDir"/*.png; do
      base="''${f##*/}"
      id="''${base#steam-game-}"
      id="''${id%.desktop}"
      id="''${id%.png}"
      [[ -n "''${seen[$id]:-}" ]] || rm -f -- "$f"
    done
    shopt -u nullglob
  '';
in
{
  systemd.user.services.steam-game-index = {
    Unit.Description = "Index installed Steam games as desktop entries";
    Service = {
      Type = "oneshot";
      ExecStart = indexerScript;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # libraryfolders.vdf lists the apps of every library — game installs and
  # uninstalls anywhere (including other drives) touch it, so watching just
  # this file covers all libraries.
  systemd.user.paths.steam-game-index = {
    Unit.Description = "Watch Steam libraries and re-index installed games";
    Path.PathChanged = [
      "%h/.local/share/Steam/config/libraryfolders.vdf"
      "%h/.local/share/Steam/steamapps"
    ];
    Install.WantedBy = [ "paths.target" ];
  };
}
