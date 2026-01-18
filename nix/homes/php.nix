{ pkgs, ... }:
let
  # Define a PHP build with all Laravel mandatory extensions
  phpWithLaravel = pkgs.php82.buildEnv {
    # Specify your extensions here (same format as withExtensions)
    extensions =
      { all, enabled }:
      with all;
      enabled
      ++ [
        bcmath
        ctype
        curl
        dom
        fileinfo
        filter
        gd
        intl
        mbstring
        openssl
        pdo
        pdo_mysql # Change to pdo_pgsql or pdo_sqlite as needed
        session
        tokenizer
        xml
        xmlwriter
        zip
      ];

    # Add your custom memory limit here
    extraConfig = ''
      memory_limit = 2G
    '';
  };
in
{
  home.packages = [
    phpWithLaravel
    pkgs.php82Packages.composer
  ];

  # Optional: Add global Composer binaries to your PATH
  home.sessionPath = [
    "$HOME/.config/composer/vendor/bin"
  ];
}
