-- lazy.nvim / plugin spec
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        explorer = {
          -- Auto-focus the list instead of search input when opened
          focus = "list",
        },
      },
    },
  },
}
