--!nonstrict
-- Bar widget for gery/notes-md: opens the notes panel, tooltip shows the
-- number of indexed notes.

local notes = require("./lib/notes.luau")

local function paint()
  local snapshot = noctalia.state.get(notes.INDEX_KEY)
  local count = 0
  if type(snapshot) == "table" and type(snapshot.count) == "number" then
    count = snapshot.count
  end
  barWidget.setGlyph("notes")
  barWidget.setTooltip(noctalia.tr("widget.tooltip", { count = tostring(count) }))
end

function update()
  noctalia.setUpdateInterval(5000)
  paint()
end

noctalia.state.watch(notes.INDEX_KEY, paint)

function onClick()
  noctalia.togglePanel(notes.PANEL_ID)
end
