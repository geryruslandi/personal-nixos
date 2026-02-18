{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # fix lutris icon not showing on launcher
    (lutris.override {
      extraLibraries = pkgs: [
        # List library dependencies here
      ];
      extraPkgs = pkgs: [
        wineWow64Packages.stable # Adds a system-wide Wine that Lutris can detect
        winetricks # Fixes "winetricks not found" errors
      ];
    })
  ];
}
