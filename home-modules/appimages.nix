{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Where raw .AppImage files are kept.
  appimageDirPath = "${config.home.homeDirectory}/Applications";
  appimageDir = /. + appimageDirPath;

  # Install an AppImage as a proper launcher-visible package: Name, Categories
  # and icon come from the AppImage's own desktop entry (falling back to
  # .DirIcon), and Exec points at an FHS-wrapped binary that runs the
  # extracted AppRun.
  #
  # Notes:
  # - `src` must be a Nix *path* (not a plain string) so the evaluator copies
  #   it into the store. Replacing a file with a new version requires a
  #   rebuild for the launcher entry to change (the store copy is
  #   content-hashed).
  # - nixpkgs' appimageTools.extract only understands squashfs payloads, so
  #   extraction is done with the AppImage's own runtime extractor, which
  #   also handles dwarfs/sharun AppImages. appimage-run (ad-hoc CLI runner)
  #   has the same squashfs-only limitation.
  # - An optional "<name>.AppImage.env" file next to the AppImage is sourced
  #   (set -a) before launch.
  mkAppImage =
    {
      pname,
      version ? "unstable",
      src,
      envFile ? null,
      extraPkgs ? _: [ ],
    }:
    let
      contents = pkgs.runCommand "${pname}-${version}-extracted" { } ''
        tmp=$(mktemp -d)
        cd "$tmp"
        ${src} --appimage-extract >/dev/null
        # squashfs runtimes extract to squashfs-root; dwarfs runtimes to AppDir
        # (and leave squashfs-root as a symlink to it)
        srcdir=""
        for d in AppDir squashfs-root; do
          if [ -d "$d" ] && [ ! -L "$d" ]; then
            srcdir="$d"
            break
          fi
        done
        if [ -z "$srcdir" ]; then
          echo "AppImage extraction produced no root directory" >&2
          exit 1
        fi
        mv "$srcdir" "$out"
      '';
      envLoader = pkgs.writeShellScript "${pname}-env-loader" ''
        if [ -f ${lib.escapeShellArg (toString envFile)} ]; then
          set -a
          . ${lib.escapeShellArg (toString envFile)}
          set +a
        fi
      '';
    in
    pkgs.appimageTools.wrapAppImage {
      inherit pname version;
      inherit extraPkgs;
      src = contents;
      nativeBuildInputs = lib.optionals (envFile != null) [ pkgs.makeWrapper ];
      extraInstallCommands = ''
        mkdir -p "$out/share/applications"

        # Desktop entry: prefer one shipped inside the AppImage
        desktop_src=""
        for candidate in \
          ${contents}/usr/share/applications/*.desktop \
          ${contents}/share/applications/*.desktop \
          ${contents}/*.desktop; do
          if [ -f "$candidate" ]; then
            desktop_src="$candidate"
            break
          fi
        done

        if [ -n "$desktop_src" ]; then
          cp "$desktop_src" "$out/share/applications/${pname}.desktop"
        else
          cat > "$out/share/applications/${pname}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${pname}
Exec=${pname} %U
Terminal=false
EOF
        fi

        # Point Exec/TryExec at the wrapper (keep field codes like %f/%U)
        sed -i "s|^Exec=[^ %]*|Exec=${pname}|" "$out/share/applications/${pname}.desktop"
        sed -i "s|^TryExec=[^ %]*|TryExec=${pname}|" "$out/share/applications/${pname}.desktop"

        # Icons: install only the icon(s) named by the entry's Icon= key,
        # preserving relative hicolor paths; fall back to .DirIcon.
        icon_name="$(sed -n 's|^Icon=||p' "$out/share/applications/${pname}.desktop")"
        if [ -z "$icon_name" ]; then
          icon_name="${pname}"
          sed -i "s|^Icon=.*|Icon=${pname}|" "$out/share/applications/${pname}.desktop"
        fi
        found_icon=0
        while IFS= read -r f; do
          rel="''${f#"${contents}/"}"
          ext="''${rel##*.}"
          case "$ext" in
            svg|svgz|png|xpm|ico) ;;
            *) continue ;;
          esac
          found_icon=1
          case "$rel" in
            usr/share/icons/*)
              install -Dm644 "$f" "$out/share/''${rel#usr/}"
              ;;
            share/icons/*)
              install -Dm644 "$f" "$out/$rel"
              ;;
            *)
              case "$ext" in
                svg|svgz) dest="$out/share/icons/hicolor/scalable/apps/$icon_name.$ext" ;;
                *) dest="$out/share/icons/hicolor/256x256/apps/$icon_name.$ext" ;;
              esac
              install -Dm644 "$f" "$dest"
              ;;
          esac
        done < <(find ${contents} -maxdepth 8 -not -type d -name "$icon_name.*")

        if [ "$found_icon" -eq 0 ] && [ -e "${contents}/.DirIcon" ]; then
          ext="$(readlink -f "${contents}/.DirIcon")"
          ext="''${ext##*.}"
          case "$ext" in
            svg) dest="$out/share/icons/hicolor/scalable/apps/$icon_name.$ext" ;;
            *) dest="$out/share/icons/hicolor/256x256/apps/$icon_name.png" ;;
          esac
          install -Dm644 "${contents}/.DirIcon" "$dest"
        fi
      '' + lib.optionalString (envFile != null) ''
        mv "$out/bin/${pname}" "$out/bin/.${pname}-unwrapped"
        makeWrapper "$out/bin/.${pname}-unwrapped" "$out/bin/${pname}" \
          --run "${envLoader}"
      '';
    };

  # Discover *.AppImage files at eval time — drop a file in ~/Applications,
  # rebuild, and it shows up in the launcher. No per-app code needed.
  appimageFiles = lib.filterAttrs (
    name: type:
    type == "regular"
    && (lib.hasSuffix ".AppImage" name || lib.hasSuffix ".appimage" name)
  ) (if builtins.pathExists appimageDir then builtins.readDir appimageDir else { });

  discoveredApps = lib.mapAttrsToList (
    name: _:
    mkAppImage {
      pname = lib.removeSuffix ".appimage" (lib.removeSuffix ".AppImage" name);
      src = appimageDir + "/${name}";
      envFile =
        let
          env = appimageDir + "/${name}.env";
        in
        if builtins.pathExists env then env else null;
    }
  ) appimageFiles;
in
{
  # Keep the directory present on fresh machines so there's somewhere to drop
  # AppImages.
  home.file."Applications/.keep".text = "";

  home.packages = discoveredApps;
}
