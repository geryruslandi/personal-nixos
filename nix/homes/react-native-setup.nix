{
  pkgs,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    android-studio
  ];

  home.sessionVariables = {
    ANDROID_HOME = "$HOME/Android/Sdk";
  };

  home.sessionPath = [
    "$HOME/Android/Sdk/emulator"
    "$HOME/Android/Sdk/platform-tools"
  ];
}
