return {
  "lewis6991/gitsigns.nvim",
  opts = {
    current_line_blame = true, -- Shows VS Code style inline commit author
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = "eol", -- Places text at the end of the line
      delay = 200,           -- Delay in milliseconds before text appears
    },
    current_line_blame_formatter =
    "                                                       <author>, <author_time:%d-%m-%Y> • <summary>",
  },
}
