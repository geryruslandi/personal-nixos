{
  ...
}:
{
  # lsfg-vk v2 profile configuration (schema is strict: unknown keys throw,
  # so this must stay in lockstep with upstream rc1's parser).
  # Managed declaratively — regenerate via rebuild; multiplier / flow_scale /
  # performance_mode are hot-reloaded by the layer while a game is running.
  #
  # Per-game enabling (profile matching order):
  #   1. exe path endswith active_in entry   ("eden", "TotalWarhammer3")
  #   2. wine exe path endswith entry        ("Cyberpunk2077.exe", "DarkSoulsRemastered.exe")
  #   3. process name equals entry
  #   4. $SteamAppId equals entry            ("1091500", "1142710")
  # Per-launch overrides: LSFGVK_PROFILE=<name> to force, DISABLE_LSFGVK=1 to
  # disable. Requires V-Sync enabled in-game (pacing = vsync).
  xdg.configFile."lsfg-vk/conf.toml".text = ''
    version = 2

    [global]
    allow_fp16 = true

    # Upstream's smoke test profile: vkcube runs at 4x performance-mode FG
    # (compare with: DISABLE_LSFGVK=1 vkcube)
    [[profile]]
    name = "vkcube check"
    active_in = ["vkcube", "vkcubepp"]
    multiplier = 4
    flow_scale = 0.85
    performance_mode = true

    [[profile]]
    name = "Starter"
    active_in = [
      "1091500",                 # Steam — Cyberpunk 2077 (SteamAppId env)
      "Cyberpunk2077.exe",       # …or by Windows exe under Proton
      "1142710",                 # Steam — Total War WARHAMMER III (SteamAppId env)
      "TotalWarhammer3",         # …or by native Linux binary (Feral port)
      "DarkSoulsRemastered.exe", # Lutris — Dark Souls Remastered (wine exe)
      "eden",                    # Eden emulator (applies to every Eden game)
    ]
    multiplier = 2
    flow_scale = 0.85
    performance_mode = false
  '';
}
