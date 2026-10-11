--!nonstrict
-- Bar capsule: pending task count, flagged when anything is overdue. Click opens
-- the panel. Reads noctalia.state only — the service owns the CLI.

local note = require("./lib/note.luau")

local counts = nil
local failure = note.NO_FAILURE

local function render()
  local color, glyph, text, tooltip

  if failure.code ~= "" then
    color = note.COLOR.error
    glyph = failure.code == "not_installed" and "list-check" or "alert-triangle"
    text = "!"
    tooltip = {
      noctalia.tr("ui.title"),
      noctalia.tr("ui.error." .. failure.code),
      failure.detail ~= "" and failure.detail or "",
    }
  elseif counts == nil then
    color = "on_surface_variant"
    glyph = "list-check"
    text = noctalia.tr("ui.dash")
    tooltip = { noctalia.tr("ui.title"), noctalia.tr("ui.loading") }
  else
    local pending = counts.pending or 0
    local overdue = counts.overdue or 0
    if overdue > 0 then
      color = note.COLOR.overdue
      glyph = "alert-triangle"
    elseif pending > 0 then
      color = note.COLOR.ok
      glyph = "list-check"
    else
      color = "on_surface_variant"
      glyph = "list-check"
    end
    text = tostring(pending)
    tooltip = {
      noctalia.tr("ui.title"),
      noctalia.tr("ui.tooltip.pending", { count = pending }),
      noctalia.tr("ui.tooltip.overdue", { count = overdue }),
      noctalia.tr("ui.tooltip.due_today", { count = counts.due_today or 0 }),
      noctalia.tr("ui.tooltip.done", { count = counts.done or 0 }),
      "",
      noctalia.tr("ui.tooltip.hint"),
    }
  end

  barWidget.setGlyph(glyph)
  barWidget.setGlyphColor(color)
  barWidget.setColor(color)
  barWidget.setText(text)
  -- Drop empty lines (a failed read has no detail).
  local lines = {}
  for _, line in ipairs(tooltip or {}) do
    if line ~= "" then lines[#lines + 1] = line end
  end
  barWidget.setTooltip(table.concat(lines, "\n"))
end

noctalia.state.watch("counts", function(value)
  counts = value
  render()
end)

noctalia.state.watch("error", function(value)
  failure = note.asFailure(value)
  render()
end)

function update()
  local c = noctalia.state.get("counts")
  if c ~= nil then counts = c end
  failure = note.asFailure(noctalia.state.get("error"))
  render()
end

function onClick()
  noctalia.togglePanel("gery/note-tuxedo:todo-panel")
end

counts = noctalia.state.get("counts")
failure = note.asFailure(noctalia.state.get("error"))
noctalia.setUpdateInterval(30000)
render()
