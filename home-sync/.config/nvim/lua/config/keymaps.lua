-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Quick exit from insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit Insert Mode" })
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit Insert Mode" })

-- Line start/end (leaves Shift+H / Shift+L free for LazyVim buffer tabs)
vim.keymap.set({ "n", "v" }, "gl", "$", { desc = "End of line" })
vim.keymap.set({ "n", "v" }, "gh", "^", { desc = "Start of line" })

-- To exit terminal
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- To delete without yank (prevent 'cut' behavior on visual delete)
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete without copying" })

-- Show file on snack explorer (hidden + ignored, follow buffer file)
vim.keymap.set("n", "<leader>fe", function()
  Snacks.explorer.open({
    follow_file = true,
    ignored = true,
    hidden = true,
  })
end, { desc = "Explorer (Hidden+Ignored, Follow File)" })

-- Default explorer (root dir), clean of hidden/ignored
vim.keymap.set("n", "<leader>e", function()
  Snacks.explorer.open({ cwd = LazyVim.root() })
end, { desc = "Explorer (Root Dir)" })
