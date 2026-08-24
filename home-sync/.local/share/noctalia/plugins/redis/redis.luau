noctalia.setUpdateInterval(3000)

local UNIT   = "redis.service"
local LABEL  = "Redis"
local GLYPH  = "database"
local GLYPH_OFF = "database-off"

local COLOR_RUNNING = "#4ade80"
local COLOR_STOPPED = "#f87171"
local COLOR_FAIL    = "#fb7185"
local COLOR_WORKING = "#fbbf24"
local COLOR_MISSING = "#64748b"

local installed = nil
local state     = "unknown"
local enabled   = "unknown"
local sinceSec  = nil
local port      = noctalia.getConfig("port") or 6379

local function fmtDuration(sec)
  if not sec or sec < 0 then return nil end
  sec = math.floor(sec + 0.5)
  if sec < 60 then return sec .. "s" end
  local m = math.floor(sec / 60)
  if m < 60 then return m .. "m" end
  local h = math.floor(m / 60)
  local d = math.floor(h / 24)
  m = m % 60
  h = h % 24
  if d > 0 then return d .. "d " .. h .. "h" end
  return h .. "h " .. m .. "m"
end

local function splitLines(out)
  local lines = {}
  if out then
    for line in (out .. "\n"):gmatch("(.-)\n") do
      line = line:gsub("\r$", "")
      if #line > 0 then table.insert(lines, line) end
    end
  end
  return lines
end

local function tooltip(statusLine)
  local lines = { LABEL, statusLine, "Port: " .. port }
  if state == "active" or state == "failed" then
    local up = fmtDuration(sinceSec)
    if up then table.insert(lines, "Uptime: " .. up) end
  end
  table.insert(lines, "Enabled: " .. enabled)
  table.insert(lines, "Click to " .. (state == "active" and "stop" or "start"))
  return table.concat(lines, "\n")
end

local function render()
  if installed == false then
    barWidget.setGlyph(GLYPH)
    barWidget.setGlyphColor(COLOR_MISSING)
    barWidget.setColor(COLOR_MISSING)
    barWidget.setText(LABEL)
    barWidget.setTooltip(LABEL .. "\nService not installed on this system")
    return
  end

  if state == "active" then
    barWidget.setGlyph(GLYPH)
    barWidget.setGlyphColor(COLOR_RUNNING)
    barWidget.setColor(COLOR_RUNNING)
    barWidget.setTooltip(tooltip("Status: Running"))
  elseif state == "failed" then
    barWidget.setGlyph("alert-octagon")
    barWidget.setGlyphColor(COLOR_FAIL)
    barWidget.setColor(COLOR_FAIL)
    barWidget.setTooltip(tooltip("Status: Failed"))
  elseif state == "inactive" then
    barWidget.setGlyph(GLYPH_OFF)
    barWidget.setGlyphColor(COLOR_STOPPED)
    barWidget.setColor(COLOR_STOPPED)
    barWidget.setTooltip(tooltip("Status: Stopped"))
  else
    barWidget.setGlyph(GLYPH)
    barWidget.setGlyphColor(COLOR_WORKING)
    barWidget.setColor(COLOR_WORKING)
    barWidget.setTooltip(tooltip("Status: " .. state))
  end
  barWidget.setText(LABEL)
end

local function poll()
  local cmd = table.concat({
    "systemctl is-active " .. UNIT,
    "systemctl is-enabled " .. UNIT .. " 2>&1",
    "awk '{print $1}' /proc/uptime",
    "systemctl show " .. UNIT .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local enabledOut = lines[2] or ""
    installed = enabledOut ~= "not-found"
      and not string.find(enabledOut, "No such file or directory", 1, true)
      and not string.find(enabledOut, "Failed to get unit file state", 1, true)
    if not installed then
      render()
      return
    end
    state = lines[1] or "unknown"
    enabled = enabledOut
    sinceSec = nil
    if lines[3] and lines[4] then
      local sysUp = tonumber(lines[3])
      local monoUs = tonumber(lines[4])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    render()
  end)
  if not ok then
    state = "error"
    render()
  end
end

function update()
  poll()
end

function onClick()
  if installed == false then
    noctalia.notify(LABEL .. " not installed", "This service is not installed on the system.")
    return
  end
  if state == "active" then
    noctalia.runAsync("systemctl stop " .. UNIT, poll)
  else
    noctalia.runAsync("systemctl start " .. UNIT, poll)
  end
end
