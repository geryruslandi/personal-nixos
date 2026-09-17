-- ~/.config/nvim/lua/plugins/no-neck-pain.lua
return {
  "shortcuts/no-neck-pain.nvim",
  cmd = { "NoNeckPain" },
  keys = {
    { "<leader>uz", "<cmd>NoNeckPain<cr>", desc = "Toggle no-neck-pain" },
  },
  opts = {
    width = 200,
  },
  config = function(_, opts)
    require("no-neck-pain").setup(opts)

    -- no-neck-pain can't coexist with the snacks explorer sidebar (upstream
    -- issue #511: it's not a recognized integration, so the centered layout
    -- gets off-center and wrong width). Until upstream v3 merges, disable nnp
    -- while the explorer is open and restore it once it closes.
    local function explorer_open()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "snacks_layout_box" then
          return true
        end
      end
      return false
    end

    local function nnp_running()
      return _G.NoNeckPain ~= nil and _G.NoNeckPain.state ~= nil and _G.NoNeckPain.state.enabled
    end

    -- set true when we disabled it, so we only re-enable what we disabled
    local self_disabled = false

    -- v2 guard missing upstream: debounced internal inits can fire on
    -- torn-down state after a disable, erroring with "called the internal
    -- `init` method on a `nil` tab". Soften to a no-op.
    local main_mod = require("no-neck-pain.main")
    local real_main_init = main_mod.init
    main_mod.init = function(scope)
      if not nnp_running() then
        return
      end
      return real_main_init(scope)
    end

    local function settle()
      vim.defer_fn(function()
        local function focus_normal()
          -- nnp blows up if disabled while focus is in a floating window
          for _, win in ipairs(vim.fn.getwininfo()) do
            if vim.api.nvim_win_get_config(win.winid).relative == "" then
              pcall(vim.api.nvim_set_current_win, win.winid)
              return true
            end
          end
          return false
        end

        if explorer_open() then
          if nnp_running() and focus_normal() then
            self_disabled = true
            pcall(require("no-neck-pain").disable)
          end
        elseif self_disabled and not nnp_running() then
          self_disabled = false
          pcall(require("no-neck-pain").enable, "snacks_explorer_restore")
        end
      end, 150)
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "snacks_layout_box",
      callback = function()
        settle()
      end,
      desc = "no-neck-pain: disable while snacks explorer is open",
    })

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = "*",
      callback = function()
        settle()
      end,
      desc = "no-neck-pain: restore after snacks explorer closes",
    })
  end,
}
