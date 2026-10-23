--!nonstrict
local ak = require("./lib/ak820.luau")

local state = nil

local function tooltip()
  if state == nil or state.connected ~= true then
    return noctalia.tr("ui.widget.disconnected")
  end
  local panel = state.panel or ak.load_panel()
  return table.concat({
    noctalia.tr("ui.title"),
    noctalia.tr("ui.widget.connected"),
    noctalia.tr("ui.widget.effect", { effect = noctalia.tr("ui.effect." .. panel.effect) }),
    noctalia.tr("ui.widget.screen", { screen = noctalia.tr("ui.screen." .. panel.screen) }),
  }, "\n")
end

local function render()
  local connected = state ~= nil and state.connected == true
  local panel = (state ~= nil and state.panel) or ak.load_panel()
  barWidget.setGlyph("keyboard")
  barWidget.setGlyphColor(connected and panel.color or "on_surface_variant/0.55")
  barWidget.setColor(connected and "on_surface" or "on_surface_variant/0.55")
  barWidget.setText("")
  barWidget.setTooltip(tooltip())
end

function update()
  local value = noctalia.state.get("ak820")
  if value ~= nil then
    state = value
  end
  render()
end

function onClick()
  noctalia.togglePanel(ak.PANEL_ID)
end

noctalia.state.watch("ak820", function(value)
  state = value
  render()
end)

noctalia.setUpdateInterval(5000)
render()
