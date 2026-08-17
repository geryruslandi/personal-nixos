{ pkgs, ... }:
{
  home.packages = with pkgs; [
    neovim

    # LazyVim external dependencies
    ripgrep
    fd
    lazygit
    fzf

    # Treesitter compilation
    gcc
    tree-sitter

    # Snacks.nvim rendering tools
    trash-cli
    ghostscript_headless
    tectonic
    mermaid-cli

    # Mason install prerequisites (nil_ls builds via cargo, stylua needs unzip)
    cargo
    unzip

    # Nix language toolchain (LazyVim extra lang.nix)
    statix
    nil
    alejandra
  ];
}
