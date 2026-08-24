noctalia.setUpdateInterval(5000)

local WARP = "warp-cli"
local DAEMON = "cloudflare-warp.service"

local COLOR_RUNNING = "#4ade80"
local COLOR_STOPPED = "#f87171"
local COLOR_WORKING = "#fbbf24"
local COLOR_MISSING = "#64748b"

local state = "unknown"
local enabled = "unknown"
local sinceSec = nil
local busy = false

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

local function detailLines()
  local lines = {}
  local up = fmtDuration(sinceSec)
  if up then table.insert(lines, "Uptime: " .. up) end
  table.insert(lines, "Enabled: " .. enabled)
  return lines
end

local function render()
  barWidget.setText("WARP")
  if state == "no-cli" then
    barWidget.setGlyph("alert-triangle")
    barWidget.setColor(COLOR_MISSING)
    barWidget.setGlyphColor(COLOR_MISSING)
    barWidget.setTooltip("warp-cli not installed\nInstall the cloudflare-warp package to use this toggle.")
  elseif state == "not-registered" then
    barWidget.setGlyph("shield-x")
    barWidget.setColor(COLOR_STOPPED)
    barWidget.setGlyphColor(COLOR_STOPPED)
    barWidget.setTooltip("warp-cli not registered\nRun: sudo warp-cli registration new")
  elseif state == "connecting" then
    barWidget.setGlyph("shield")
    barWidget.setColor(COLOR_WORKING)
    barWidget.setGlyphColor(COLOR_WORKING)
    barWidget.setTooltip("Turning on Cloudflare WARP\u{2026}")
  elseif state == "disconnecting" then
    barWidget.setGlyph("shield")
    barWidget.setColor(COLOR_WORKING)
    barWidget.setGlyphColor(COLOR_WORKING)
    barWidget.setTooltip("Turning off Cloudflare WARP\u{2026}")
  elseif state == "connected" then
    barWidget.setGlyph("shield-check")
    barWidget.setColor(COLOR_RUNNING)
    barWidget.setGlyphColor(COLOR_RUNNING)
    local lines = { "Cloudflare WARP: connected" }
    for _, l in ipairs(detailLines()) do table.insert(lines, l) end
    table.insert(lines, "Click to turn off")
    barWidget.setTooltip(table.concat(lines, "\n"))
  elseif state == "daemon-off" then
    barWidget.setGlyph("shield-off")
    barWidget.setColor(COLOR_STOPPED)
    barWidget.setGlyphColor(COLOR_STOPPED)
    barWidget.setTooltip("Cloudflare WARP is off\nEnabled: " .. enabled .. "\nClick to turn on")
  else
    barWidget.setGlyph("shield-off")
    barWidget.setColor(COLOR_STOPPED)
    barWidget.setGlyphColor(COLOR_STOPPED)
    local lines = { "Cloudflare WARP: disconnected" }
    for _, l in ipairs(detailLines()) do table.insert(lines, l) end
    table.insert(lines, "Click to turn on")
    barWidget.setTooltip(table.concat(lines, "\n"))
  end
end

local function pollStatus()
  local ok = noctalia.runAsync(WARP .. " status", function(res)
    if res and res.exitCode == 0 then
      local out = res.stdout or ""
      if out:find("Disconnected", 1, true) then
        state = "disconnected"
      elseif out:find("Connected", 1, true) then
        state = "connected"
      else
        state = "disconnected"
      end
    else
      state = "disconnected"
    end
    render()
  end)
  if not ok then
    state = "disconnected"
    render()
  end
end

local function pollRegistration()
  local ok = noctalia.runAsync(WARP .. " registration show", function(res)
    if res and res.exitCode == 0 then
      pollStatus()
    else
      state = "not-registered"
      render()
    end
  end)
  if not ok then
    state = "not-registered"
    render()
  end
end

local function pollDaemon()
  local cmd = table.concat({
    "systemctl is-active " .. DAEMON,
    "systemctl is-enabled " .. DAEMON .. " 2>&1",
    "awk '{print $1}' /proc/uptime",
    "systemctl show " .. DAEMON .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local out = lines[1] or ""
    enabled = lines[2] or "unknown"
    sinceSec = nil
    if lines[3] and lines[4] then
      local sysUp = tonumber(lines[3])
      local monoUs = tonumber(lines[4])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    if out:match("^active") then
      pollRegistration()
    else
      state = "daemon-off"
      render()
    end
  end)
  if not ok then
    state = "daemon-off"
    render()
  end
end

local function refresh()
  if not noctalia.commandExists(WARP) then
    state = "no-cli"
    render()
    return
  end
  pollDaemon()
end

local function afterToggle()
  busy = false
  refresh()
end

local function toggleOff()
  if busy then return end
  busy = true
  state = "disconnecting"
  render()
  local cmd = WARP .. " disconnect; systemctl stop " .. DAEMON
  noctalia.runAsync(cmd, afterToggle)
end

local function toggleOn()
  if busy then return end
  busy = true
  state = "connecting"
  render()
  local cmd = "systemctl start " .. DAEMON
    .. " && sleep 1"
    .. " && " .. WARP .. " registration show >/dev/null 2>&1"
    .. " && for i in 1 2 3 4 5 6 7 8 9 10; do " .. WARP .. " connect && break; sleep 1; done"
  noctalia.runAsync(cmd, afterToggle)
end

function update()
  if busy then return end
  refresh()
end

function onClick()
  if busy then return end
  if state == "connected" then
    toggleOff()
  elseif state == "disconnected" or state == "daemon-off" then
    toggleOn()
  elseif state == "no-cli" then
    noctalia.notify("warp-cli not installed", "Install the cloudflare-warp package to use this toggle.")
  elseif state == "not-registered" then
    noctalia.notify("warp-cli not registered", "Run: sudo warp-cli registration new")
  end
end
