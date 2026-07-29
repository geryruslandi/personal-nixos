{ pkgs, ... }:
let
  commonExtensions =
    { all, enabled }:
    with all;
    (builtins.filter (e: e != xml) enabled)
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
      pdo_mysql
      session
      tokenizer
      xmlwriter
      zip
    ];

  phpWithLaravel = pkgs.php83.buildEnv {
    extensions = commonExtensions;
    extraConfig = "memory_limit = -1";
  };

  php82WithLaravel = pkgs.php82.buildEnv {
    extensions = commonExtensions;
    extraConfig = "memory_limit = -1";
  };
in
{
  home.packages = [
    phpWithLaravel                   # `php` = 8.3 with full extensions
    (pkgs.writeShellScriptBin "php82" ''
      exec ${php82WithLaravel}/bin/php "$@"
    '')
    pkgs.php83Packages.composer      # `composer` — compiled with PHP 8.3
    (pkgs.writeShellScriptBin "composer82" ''
      exec ${pkgs.php82Packages.composer}/bin/composer "$@"
    '')
    pkgs.php82Packages.php-codesniffer
  ];

  home.sessionPath = [
    "$HOME/.config/composer/vendor/bin"
  ];
}
