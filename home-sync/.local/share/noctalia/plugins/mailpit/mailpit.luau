noctalia.setUpdateInterval(3000)

local UNIT     = "mailpit.service"
local LABEL    = "Mailpit"
local GLYPH    = "mail-check"
local GLYPH_OFF = "mail-off"

local COLOR_RUNNING = "#4ade80"
local COLOR_STOPPED = "#f87171"
local COLOR_FAIL    = "#fb7185"
local COLOR_WORKING = "#fbbf24"
local COLOR_MISSING = "#64748b"

local installed = nil
local state     = "unknown"
local sinceSec  = nil
local busy      = false
local bootStart = false

-- Service declaration (this plugin owns it; Nix only installs the binary).
local function cfg(k, def)
  local v = noctalia.getConfig(k)
  if v == nil then return def end
  return v
end

local binary   = cfg("binary", "mailpit")
local smtpPort = cfg("smtpPort", 1025)
local uiPort   = cfg("uiPort", 8025)
local autoStart = cfg("auto_start", false)

local function unitStartCmd()
  local bin = binary
  if string.sub(binary, 1, 1) ~= "/" then
    bin = noctalia.expandPath(binary) or binary
  end
  return "systemctl --user reset-failed " .. UNIT .. " 2>/dev/null"
    .. "; systemd-run --user --unit=mailpit --collect"
    .. "  --property=Restart=on-failure --property=RestartSec=3"
    .. "  -- " .. bin .. " --smtp 127.0.0.1:" .. tostring(smtpPort)
    .. " --listen 127.0.0.1:" .. tostring(uiPort)
end

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
  local lines = { LABEL, statusLine, "SMTP: " .. smtpPort, "UI: " .. uiPort }
  if state == "active" or state == "failed" then
    local up = fmtDuration(sinceSec)
    if up then table.insert(lines, "Uptime: " .. up) end
  end
  table.insert(lines, "Type: Transient")
  table.insert(lines, "Click to " .. (state == "active" and "stop" or "start"))
  return table.concat(lines, "\n")
end

local function render()
  if installed == false then
    barWidget.setGlyph(GLYPH)
    barWidget.setGlyphColor(COLOR_MISSING)
    barWidget.setColor(COLOR_MISSING)
    barWidget.setText(LABEL)
    barWidget.setTooltip(LABEL .. "\n" .. binary .. " not installed on this system")
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

local function binaryAvailable()
  local b = binary
  if string.sub(b, 1, 1) == "/" then
    return noctalia.fileExists(b)
  end
  return noctalia.commandExists(b)
end

local function startUnit()
  if busy then return end
  busy = true
  noctalia.runAsync(unitStartCmd(), function(res)
    busy = false
    if not res or res.exitCode ~= 0 then
      noctalia.notify(LABEL .. " failed to start", (res and res.stderr or "") or "systemd-run error")
    end
    poll()
  end)
end

local function poll()
  local cmd = table.concat({
    "systemctl --user is-active " .. UNIT,
    "awk '{print $1}' /proc/uptime",
    "systemctl --user show " .. UNIT .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    installed = binaryAvailable()
    if not installed then
      render()
      return
    end
    state = lines[1] or "unknown"
    sinceSec = nil
    if lines[2] and lines[3] then
      local sysUp = tonumber(lines[2])
      local monoUs = tonumber(lines[3])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    if not bootStart and autoStart and state ~= "active" then
      bootStart = true
      startUnit()
      return
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
  if busy then return end
  if installed == false then
    noctalia.notify(LABEL .. " not installed", "The " .. binary .. " binary is not available on the system.")
    return
  end
  if state == "active" then
    noctalia.runAsync("systemctl --user stop " .. UNIT, poll)
  else
    startUnit()
  end
end

function onConfigChanged()
  binary    = cfg("binary", "mailpit")
  smtpPort  = cfg("smtpPort", 1025)
  uiPort    = cfg("uiPort", 8025)
  autoStart = cfg("auto_start", false)
  poll()
end
