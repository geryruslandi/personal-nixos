-- Panel: categorized list of services in state-colored pill rows.
-- Each pill shows name, status dot, per-service details (ports, uptime).
-- Clicking anywhere on a pill toggles the service (no switch UI).
-- Green = running, red = stopped, yellow = starting/stopping in progress.

local services = require("./lib/services.luau")

local state = nil
local seq = 0
local hovered = {}
local lastToggle = {}
local render = nil

local THEME = {
  running = { fill = "#4ade8026", fillHover = "#4ade8040", color = "#4ade80" },
  stopped = { fill = "#f8717126", fillHover = "#f8717140", color = "#f87171" },
  working = { fill = "#fbbf2426", fillHover = "#fbbf2440", color = "#fbbf24" },
  failed  = { fill = "#fb718526", fillHover = "#fb718540", color = "#fb7185" },
  missing = { fill = "#64748b26", fillHover = "#64748b40", color = "#64748b" },
}

local function isRunning(s)
  return s.state == "active" or s.state == "connected"
end

local function isWorking(s)
  return s.state == "connecting" or s.state == "disconnecting"
end

local function themeFor(s)
  if s.available == false then return THEME.missing end
  if s.state == "failed" then return THEME.failed end
  if isWorking(s) then return THEME.working end
  if isRunning(s) then return THEME.running end
  return THEME.stopped
end

local function statusText(s)
  if s.available == false then return "Not installed" end
  if s.state == "active" or s.state == "connected" then return "Running" end
  if s.state == "failed" then return "Failed" end
  if s.state == "connecting" then return "Starting\u{2026}" end
  if s.state == "disconnecting" then return "Stopping\u{2026}" end
  return "Stopped"
end

local function rowGlyph(service, s)
  local glyph = service.glyphOff or service.glyph
  if isRunning(s) then glyph = service.glyph end
  if s.state == "failed" then glyph = "alert-octagon" end
  if isWorking(s) then glyph = service.glyph end
  return glyph
end

local function toggleService(id, on)
  local now = noctalia.nowMs()
  local last = lastToggle[id] or 0
  if now - last < 300 then return end
  lastToggle[id] = now
  seq = seq + 1
  noctalia.state.set("toggleRequest", { seq = seq, id = id, action = on and "start" or "stop" })
end

local function serviceRow(service)
  local s = state and state[service.id] or nil
  if s == nil then s = { state = "unknown", available = nil, sinceSec = nil, enabled = "unknown", busy = false } end
  local running = isRunning(s)
  local canToggle = s.available ~= false and not s.busy
  local theme = themeFor(s)
  local fill = theme.fill
  if hovered[service.id] and canToggle then fill = theme.fillHover end

  local detail = services.detail(service, s)

  local onHover = nil
  if canToggle then
    onHover = function(hovering)
      hovered[service.id] = hovering == "true"
      render()
    end
  end

  return ui.row({
    key = service.id,
    gap = 10,
    paddingH = 12,
    paddingV = 9,
    radius = 10,
    fill = fill,
    border = theme.color .. "40",
    borderWidth = 1,
    align = "center",
    onClick = canToggle and function()
      toggleService(service.id, not running)
    end or nil,
    onHover = onHover,
  }, {
    ui.glyph({ name = rowGlyph(service, s), size = 18, color = theme.color }),
    ui.column({ gap = 2, flexGrow = 1, align = "stretch" }, {
      ui.label({ text = service.label, fontSize = 13, color = "on_surface", fontWeight = "medium" }),
      ui.label({
        text = "\u{25cf} " .. statusText(s) .. "  \u{00b7}  " .. detail,
        fontSize = 11,
        color = theme.color,
        maxLines = 2,
      }),
    }),
  })
end

local function buildTree()
  local children = {}
  for _, cat in ipairs(services.CATEGORIES) do
    local catRows = {}
    for _, s in ipairs(services.SERVICES) do
      if s.category == cat.id then
        table.insert(catRows, serviceRow(s))
      end
    end
    if #catRows > 0 then
      table.insert(children, ui.label({
        key = "hdr-" .. cat.id,
        text = cat.label,
        fontSize = 11,
        color = "primary",
        fontWeight = "bold",
      }))
      table.insert(children, ui.column({ key = "cat-" .. cat.id, gap = 6, paddingH = 4 }, catRows))
    end
  end

  return ui.scroll({ key = "scroll", flexGrow = 1 }, {
    ui.column({ key = "content", gap = 10, padding = 12 }, children),
  })
end

render = function()
  panel.render(buildTree())
end

noctalia.state.watch("services", function(value)
  state = value
  render()
end)

function onOpen()
  state = noctalia.state.get("services")
  hovered = {}
  render()
end
