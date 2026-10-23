--!nonstrict
local ak = require("./lib/ak820.luau")

local function matches(query, title)
  if query == "" then
    return true
  end
  return title:lower():find(query, 1, true) ~= nil
end

local function add(results, query, id, title, subtitle, glyph, result_query)
  if not matches(query, title) then
    return
  end
  results[#results + 1] = {
    id = id,
    title = title,
    subtitle = subtitle,
    glyph = glyph,
    query = result_query,
  }
end

function onQuery(text)
  text = text or ""
  noctalia.log("ajazz launcher query: '" .. text .. "'")
  local query = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  query = query:gsub("^/ajazz%s*", "")
  if query == "open" or query == "panel" then
    if noctalia.state.get("panelOpen") ~= true then
      noctalia.togglePanel(ak.PANEL_ID)
    end
    launcher.setResults(text, {
      {
        id = "act:opened",
        title = noctalia.tr("ui.launcher.open"),
        subtitle = noctalia.tr("ui.launcher.opened"),
        glyph = "keyboard",
      },
    })
    return
  end
  local state = noctalia.state.get("ak820") or {}
  local panel = state.panel or ak.load_panel()
  local connected = state.connected == true
  local results = {}

  add(
    results,
    query,
    "act:open",
    noctalia.tr("ui.launcher.open"),
    noctalia.tr(connected and "ui.launcher.connected" or "ui.launcher.not_connected"),
    "keyboard",
    "/ajazz open"
  )
  add(
    results,
    query,
    "act:clock",
    noctalia.tr("ui.launcher.clock"),
    noctalia.tr("ui.launcher.clock_sub"),
    "clock"
  )
  add(
    results,
    query,
    "act:screen:clock",
    noctalia.tr("ui.launcher.screen_clock"),
    noctalia.tr("ui.launcher.screen_clock_sub"),
    "clock"
  )
  add(
    results,
    query,
    "act:screen:cpu",
    noctalia.tr("ui.launcher.screen_cpu"),
    noctalia.tr("ui.launcher.screen_cpu_sub"),
    "cpu"
  )
  add(
    results,
    query,
    "act:effect:off",
    noctalia.tr("ui.launcher.off"),
    noctalia.tr("ui.launcher.current", { value = noctalia.tr("ui.effect." .. panel.effect) }),
    "bulb-off"
  )
  add(
    results,
    query,
    "act:effect:static",
    noctalia.tr("ui.launcher.static"),
    noctalia.tr("ui.launcher.current", { value = panel.color }),
    "bulb"
  )

  launcher.setResults(text, results)
end

function onActivate(id)
  noctalia.log("ajazz launcher activate: " .. tostring(id))
  if id == "act:open" then
    if noctalia.state.get("panelOpen") ~= true then
      noctalia.togglePanel(ak.PANEL_ID)
    end
  elseif id == "act:clock" then
    ak.request("clock_sync")
  elseif id == "act:screen:clock" then
    ak.request("patch", { patch = { screen = "clock" } })
  elseif id == "act:screen:cpu" then
    ak.request("patch", { patch = { screen = "cpu" } })
  elseif id == "act:effect:off" then
    ak.request("patch", { patch = { effect = "off" } })
  elseif id == "act:effect:static" then
    ak.request("patch", { patch = { effect = "static" } })
  end
end
