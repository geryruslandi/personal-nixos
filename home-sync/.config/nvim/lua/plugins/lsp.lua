return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        phpactor = { enabled = false },
        intelephense = {},
        nil_ls = {},
      },
    },
  },
}
