-- Bar widget: general services icon + count of running services.
-- Click toggles the services panel.

local services = require("./lib/services.luau")

local state = nil
local running = 0
local anyFailed = false
local anyWorking = false

local function isRunning(s)
  return s.state == "active" or s.state == "connected"
end

local function recompute()
  running = 0
  anyFailed = false
  anyWorking = false
  for _, s in ipairs(services.SERVICES) do
    local st = state and state[s.id] or nil
    if st then
      if isRunning(st) then
        running = running + 1
      elseif st.state == "failed" then
        anyFailed = true
      elseif st.state == "connecting" or st.state == "disconnecting" then
        anyWorking = true
      end
    end
  end
end

local function render()
  if state == nil then
    barWidget.setGlyph("server")
    barWidget.setGlyphColor(services.COLOR_MISSING)
    barWidget.setColor(services.COLOR_MISSING)
    barWidget.setText("?")
    barWidget.setTooltip("Services\nPolling\u{2026}")
    return
  end

  local lines = { "Services: " .. running .. "/" .. #services.SERVICES .. " running" }
  for _, s in ipairs(services.SERVICES) do
    local st = state[s.id]
    if not st then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": unknown")
    elseif st.available == false then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": not installed")
    elseif st.state == "active" or st.state == "connected" then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": running")
    elseif st.state == "failed" then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": failed")
    elseif st.state == "connecting" or st.state == "disconnecting" then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": working\u{2026}")
    elseif st.state == "no-session" then
      table.insert(lines, "  \u{00b7} " .. s.label .. ": container only")
    else
      table.insert(lines, "  \u{00b7} " .. s.label .. ": stopped")
    end
  end
  table.insert(lines, "Click to toggle services")
  barWidget.setTooltip(table.concat(lines, "\n"))

  local color = services.COLOR_STOPPED
  local glyph = "server"
  if running > 0 then
    color = services.COLOR_RUNNING
  elseif anyFailed then
    color = services.COLOR_FAIL
    glyph = "alert-octagon"
  elseif anyWorking then
    color = services.COLOR_WORKING
  end

  barWidget.setGlyph(glyph)
  barWidget.setGlyphColor(color)
  barWidget.setColor(color)
  barWidget.setText(tostring(running))
end

noctalia.state.watch("services", function(value)
  state = value
  recompute()
  render()
end)

function update()
  local v = noctalia.state.get("services")
  if v ~= nil then
    state = v
    recompute()
    render()
  end
end

function onClick()
  noctalia.togglePanel("gery/services:services-panel")
end
