{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    pkgs.php81Packages.composer
  ];

  programs.php = {
    enable = true;
    version = "8.1";
    extensions = with pkgs.php81Packages; [
      bcmath
      ctype
      curl
      dom
      fileinfo
      filter
      gd
      hash
      iconv
      intl
      mbstring
      openssl
      pcre
      pdo
      pdo_mysql # Or pdo_pgsql / pdo_sqlite depending on your DB
      session
      tokenizer
      xml
      xmlwriter
      zip
    ];
  };
}
