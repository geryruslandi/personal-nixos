--!nonstrict
-- Generic readonly viewer panel (item notes, long values). Content comes from
-- `noctalia.state "viewer"`: { title, body, label, sensitive }.

local rpc = require("./lib/rpc.luau")

rpc.init()

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function render()
  local viewer = noctalia.state.get("viewer") or {}
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = viewer.title or "", fontSize = 16, fontWeight = "bold", flexGrow = 1, maxLines = 1 }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
    ui.scroll({ flexGrow = 1, fill = "surface_variant/0.4", radius = 10, padding = 12, align = "stretch" }, {
      ui.label({ text = viewer.body or "" }),
    }),
    ui.row({ gap = 8, justify = "end" }, {
      ui.button({
        text = tr("viewer.copy"),
        variant = "primary",
        enabled = viewer.body ~= nil and viewer.body ~= "",
        onClick = function()
          rpc.notify("copy-value", {
            value = viewer.body or "",
            label = viewer.label or tr("fields.value"),
            sensitive = viewer.sensitive == true,
          })
        end,
      }),
    }),
  }))
end

function onOpen(_context)
  render()
end

noctalia.state.watch("viewer", function()
  render()
end)
