{
  pkgs,
  inputs,
  ...
}:
let
  # Spicetify packages are exposed as `legacyPackages.<system>` by the flake.
  # `extensions.adblockify` is the spicetify adblock extension (aliased as
  # `adblock`) — the native-client equivalent of the Firefox "Spotify Adblock"
  # web-player add-on. `hidePodcasts` is a small quality-of-life extra.
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Spotify's login opens the auth URL in the default browser with xdg-open/gio.
  # The default browser here is flatpak Zen, launched via the `flatpak` CLI. But
  # nixpkgs' Spotify wrapper puts `curlWithGnuTls` on LD_LIBRARY_PATH (its
  # `libcef.so` links a libcurl built against GnuTLS — symbol `CURL_GNUTLS_4`),
  # and that path is inherited by every child process. The system `flatpak`
  # therefore loads the GnuTLS libcurl instead of its own OpenSSL one and dies
  # with `version 'CURL_OPENSSL_4' not found` — the browser never opens
  # ("Redirecting to browser to complete login", no tab). This shim shadows the
  # CLI with one that drops the inherited library path: flatpak carries its own
  # RPATHs, so it works no matter what the calling process polluted.
  flatpakClean = pkgs.writeShellScriptBin "flatpak" ''
    exec env -u LD_LIBRARY_PATH -u LD_PRELOAD ${pkgs.flatpak}/bin/flatpak "$@"
  '';
in
{
  # `programs.spicetify` installs the patched `spotify` binary into home.packages
  # automatically — never add `pkgs.spotify` anywhere or it will shadow it.
  # The Noctalia bar widget `gery/spotify` launches this binary (see
  # home-modules/noctalia.nix and home-sync/.../plugins/spotify/).
  programs.spicetify = {
    enable = true;
    # Native Wayland on Hyprland (avoids XWayland scaling/blur issues).
    wayland = true;
    # Comfy theme (pinned by spicetify-nix) with its own default "Comfy" color
    # scheme. Applied at build time — changing the scheme needs a rebuild.
    #
    # `injectThemeJs = false` works around a spicetify-nix bug (upstream PR
    # #377, closed unmerged): spicetify-nix bundles Comfy's code locally as the
    # required `Extensions/theme.js` (it appends upstream's `theme.script.js`,
    # which also removes Comfy's auto-updater), but spicetify's default
    # `injectThemeJs = true` *also* injects the theme's `theme.js` — and that
    # file is just a loader for `https://comfy-themes.github.io/.../theme.script.js`.
    # Result: Comfy ran twice (two top-bar settings gears) with a second copy
    # fetched from the network. Disabling the theme-script injection leaves the
    # bundled extension as the single source of truth.
    theme = spicePkgs.themes.comfy // {
      injectThemeJs = false;
    };
    colorScheme = "Comfy";
    enabledExtensions = with spicePkgs.extensions; [
      adblockify
      hidePodcasts
    ];
  };

  # The user profile's bin dir precedes /run/current-system/sw/bin on PATH, so
  # this shadows the system flatpak for interactive/GUI launches (Spotify's
  # xdg-open, desktop entries, the flatpak export shims) while the NixOS
  # flatpak-managed-install service keeps using the system binary directly.
  #
  # `cava` drives the mini audio visualizer in the gery/spotify bar widget
  # (PipeWire capture of the default sink monitor, raw ASCII frames). It is only
  # ever run while that widget is in visualizer mode and Spotify is playing —
  # see the plugin's cava-runner.sh.
  home.packages = [
    flatpakClean
    pkgs.cava
  ];
}
