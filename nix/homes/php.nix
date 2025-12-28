{ pkgs, ... }:
let
  # Define a PHP build with all Laravel mandatory extensions
  phpWithLaravel = pkgs.php82.withExtensions ({ enabled, all }:
    enabled ++ (with all; [
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
    ])
  );
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
