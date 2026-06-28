{
  config,
  pkgs,
  lib,
  ...
}:
let
  appimageDir = "${config.home.homeDirectory}/Applications";

  # Script that scans ~/AppImages and creates .desktop entries + wrapper scripts.
  # Run this manually after adding/removing AppImages, or it runs automatically on rebuild.
  registerScript = pkgs.writeShellScriptBin "register-appimages" ''
    set -euo pipefail

    APPS_DIR="${appimageDir}"
    DESKTOP_DIR="${config.xdg.dataHome}/applications"
    BIN_DIR="${config.home.homeDirectory}/.local/bin"

    mkdir -p "$DESKTOP_DIR" "$BIN_DIR"

    # Clean up old entries from previous runs
    rm -f "$DESKTOP_DIR"/appimage-*.desktop "$BIN_DIR"/appimage-*

    echo "Scanning $APPS_DIR for AppImages..."

    for appimage in "$APPS_DIR"/*.AppImage "$APPS_DIR"/*.appimage; do
      [ -f "$appimage" ] || continue

      chmod +x "$appimage"

      # Derive a clean name and slug from the filename
      filename=$(basename "$appimage")
      name="''${filename%.AppImage}"
      name="''${name%.appimage}"
      slug=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

      # Create wrapper script — extracts once with the AppImage's own extractor,
      # caches the result, and runs the extracted AppRun directly.
      # Also sources an optional .env file alongside the AppImage for per-app variables.
      wrapper="$BIN_DIR/appimage-$slug"
      cat > "$wrapper" << WRAPPER
#!/bin/sh
set -e

# Source per-AppImage env file if it exists (e.g. EdenEmulator.AppImage.env)
env_file="$appimage.env"
if [ -f "\$env_file" ]; then
  set -a
  . "\$env_file"
  set +a
fi

cache_dir="\$HOME/.cache/appimages/$slug"

# Extract if not cached or if AppImage has been modified
if [ ! -d "\$cache_dir" ] || [ "\$cache_dir/.extracted" -ot "$appimage" ]; then
  echo "Extracting $name (cached in \$cache_dir)..."
  rm -rf "\$cache_dir"
  tmpdir=\$(mktemp -d)
  cd "\$tmpdir"
  "$appimage" --appimage-extract >/dev/null 2>&1
  if [ -d squashfs-root ]; then
    mv squashfs-root/* "\$tmpdir/" 2>/dev/null || true
    rmdir squashfs-root 2>/dev/null || true
  fi
  mkdir -p "\$(dirname "\$cache_dir")"
  mv "\$tmpdir" "\$cache_dir"
  touch "\$cache_dir/.extracted"
fi

# Find and run AppRun (might be in root or usr/bin or similar)
if [ -x "\$cache_dir/AppRun" ]; then
  exec "\$cache_dir/AppRun" "\$@"
elif [ -x "\$cache_dir/usr/bin/AppRun" ]; then
  exec "\$cache_dir/usr/bin/AppRun" "\$@"
else
  echo "Error: Could not find AppRun in extracted AppImage" >&2
  exit 1
fi
WRAPPER
      chmod +x "$wrapper"

      # Extract icon from the cached extraction or by mounting the AppImage
      icon_cache="$DESKTOP_DIR/appimage-$slug.png"
      if [ ! -f "$icon_cache" ]; then
        cached="\$HOME/.cache/appimages/$slug"
        if [ -d "\$cached" ]; then
          # Try the cache first (fast, already extracted)
          for candidate in \
            "\$cached/.DirIcon" \
            "\$cached/"*.png \
            "\$cached/usr/share/icons/hicolor/"*/*/*.png \
            "\$cached/usr/share/pixmaps/"*.png \
            "\$cached/share/icons/hicolor/"*/*/*.png \
            "\$cached/share/pixmaps/"*.png; do
            if [ -f "\$candidate" ]; then
              cp "\$candidate" "$icon_cache" 2>/dev/null && break
            fi
          done
        fi

        # Fall back to mounting if not found in cache
        if [ ! -f "$icon_cache" ]; then
          mnt=$(mktemp -d)
          if "$appimage" --appimage-mount "$mnt" &>/dev/null & then
            mount_pid=$!
            for i in $(seq 1 30); do
              if mountpoint -q "$mnt" 2>/dev/null; then break; fi
              sleep 0.1
            done

            for candidate in \
              "$mnt/.DirIcon" \
              "$mnt/"*.png \
              "$mnt/usr/share/icons/hicolor/256x256/apps/"*.png \
              "$mnt/usr/share/icons/hicolor/128x128/apps/"*.png \
              "$mnt/usr/share/icons/hicolor/64x64/apps/"*.png \
              "$mnt/usr/share/icons/hicolor/48x48/apps/"*.png \
              "$mnt/usr/share/pixmaps/"*.png \
              "$mnt/usr/share/icons/"*/*/*.png; do
              if [ -f "$candidate" ]; then
                cp "$candidate" "$icon_cache" 2>/dev/null && break
              fi
            done

            fusermount -u "$mnt" 2>/dev/null || true
            kill "$mount_pid" 2>/dev/null || true
          fi
          rmdir "$mnt" 2>/dev/null || true
        fi
      fi

      # Build the .desktop entry
      icon_line=""
      if [ -f "$icon_cache" ]; then
        icon_line="Icon=$icon_cache"
      fi

      cat > "$DESKTOP_DIR/appimage-$slug.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Comment=AppImage: $filename
Exec=$wrapper
TryExec=$wrapper
Terminal=false
Categories=Utility;
''${icon_line}
DESKTOP

      echo "  Registered: $name ($slug)"
    done

    # Refresh desktop database so launchers (wofi) pick up new entries
    if command -v update-desktop-database &>/dev/null; then
      update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    echo "Done! AppImages registered in $DESKTOP_DIR"
  '';
in
{
  # Ensure the AppImages directory exists
  home.file."Applications/.keep".text = "";

  # Provide both appimage-run and the registration script
  home.packages = [
    pkgs.appimage-run
    registerScript
  ];

  # Register AppImages automatically on each rebuild
  home.activation.registerAppImages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${appimageDir}" ] && ls "${appimageDir}"/*.AppImage "${appimageDir}"/*.appimage >/dev/null 2>&1; then
      echo "Registering AppImages..."
      ${registerScript}/bin/register-appimages
    fi
  '';

  # systemd path watcher — auto-registers AppImages instantly when files change in ~/Applications
  systemd.user.services.register-appimages = {
    Unit = {
      Description = "Register AppImages in ~/Applications as desktop entries";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${registerScript}/bin/register-appimages";
    };
  };

  systemd.user.paths.register-appimages = {
    Unit = {
      Description = "Watch ~/Applications for AppImage changes";
    };
    Path = {
      PathModified = appimageDir;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
