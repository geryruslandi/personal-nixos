{
  pkgs,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    android-studio
    jdk17
  ];

  # Manages the Java environment for this user
  programs.java = {
    enable = true;
    package = pkgs.jdk17; # You can specify pkgs.jdk17, pkgs.jdk23, etc.
  };

  home.sessionVariables = {
    ANDROID_HOME = "$HOME/Android/Sdk";
    JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
  };

  home.sessionPath = [
    "$HOME/Android/Sdk/emulator"
    "$HOME/Android/Sdk/platform-tools"
  ];
}
