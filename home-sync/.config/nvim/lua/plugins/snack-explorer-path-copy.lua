-- ~/.config/nvim/lua/plugins/snacks.lua (or wherever your snacks.nvim setup lives)
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        explorer = {
          -- 1. Register the custom action
          actions = {
            copy_selector = function(_, item)
              if not item or not item.file then
                return
              end

              local filepath = item.file
              local modify = vim.fn.fnamemodify
              local filename = modify(filepath, ":t")

              local vals = {
                ["BASENAME"] = modify(filename, ":r"),
                ["EXTENSION"] = modify(filename, ":e"),
                ["FILENAME"] = filename,
                ["PATH (CWD)"] = modify(filepath, ":."),
                ["PATH (HOME)"] = modify(filepath, ":~"),
                ["PATH"] = filepath,
                ["URI"] = vim.uri_from_fname(filepath),
              }

              local options = vim.tbl_filter(function(val)
                return vals[val] ~= ""
              end, vim.tbl_keys(vals))

              if vim.tbl_isempty(options) then
                vim.notify("No values to copy", vim.log.levels.WARN)
                return
              end

              table.sort(options)
              vim.ui.select(options, {
                prompt = "Choose to copy to clipboard:",
                format_item = function(choice)
                  return ("%s: %s"):format(choice, vals[choice])
                end,
              }, function(choice)
                local result = vals[choice]
                if result then
                  vim.fn.setreg("+", result) -- System clipboard
                  vim.fn.setreg('"', result) -- Neovim register
                  Snacks.notify.info(("Copied: `%s`"):format(result))
                end
              end)
            end,
          },
          -- 2. Bind the action to a key inside the explorer list view
          win = {
            list = {
              keys = {
                ["Y"] = "copy_selector",
              },
            },
          },
        },
      },
    },
  },
}
