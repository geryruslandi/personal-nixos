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
  ];
}
