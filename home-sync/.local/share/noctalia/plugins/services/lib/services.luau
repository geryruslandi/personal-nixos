-- Service registry for the gery/services hub plugin.
-- One entry per service; the same table drives polling (service.luau),
-- the bar widget (widget.luau) and the panel (panel.luau).

local M = {}

M.COLOR_RUNNING = "#4ade80"
M.COLOR_STOPPED = "#f87171"
M.COLOR_FAIL    = "#fb7185"
M.COLOR_WORKING = "#fbbf24"
M.COLOR_MISSING = "#64748b"

local function cfg(k, def)
  local v = noctalia.getConfig(k)
  if v == nil then return def end
  return v
end

local function expandBinary(binary)
  if string.sub(binary, 1, 1) == "/" then return binary end
  -- The plugin's runAsync subprocess may not inherit the user PATH, so bare
  -- binary names fail with "command not found". Resolve to an absolute path
  -- by searching the session PATH via noctalia.getenv + noctalia.fileExists.
  local path = noctalia.expandPath(binary)
  if path and noctalia.fileExists(path) then return path end
  local envPath = noctalia.getenv("PATH") or ""
  for dir in string.gmatch(envPath .. ":", "([^:]*):") do
    if #dir > 0 then
      local candidate = dir .. "/" .. binary
      if noctalia.fileExists(candidate) then return candidate end
    end
  end
  return binary
end

-- Shared start command builders --------------------------------------------

-- systemd-run transient user unit (seanime / stremio / mailpit)
-- NOTE: plain concat — the systemd-run invocation is ONE shell statement;
-- joining its option lines with "; " would execute them as separate commands.
local function transientStart(unit, bin, args)
  return "systemctl --user reset-failed " .. unit .. " 2>/dev/null"
    .. "; systemd-run --user --unit=" .. unit:gsub("%.service$", "") .. " --collect"
    .. " --property=Restart=on-failure --property=RestartSec=3"
    .. " -- " .. expandBinary(bin) .. (args and (" " .. args) or "")
end

-- Registry ------------------------------------------------------------------

M.SERVICES = {
  {
    id       = "redis",
    label    = "Redis",
    category = "development",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "system",
    kind     = "systemd",
    unit     = "redis.service",
    ports    = { { name = "Port", value = cfg("redis_port", 6379), configKey = "redis_port", def = 6379 } },
  },
  {
    id       = "mysql",
    label    = "MySQL",
    category = "development",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "system",
    kind     = "systemd",
    unit     = "mysql.service",
    ports    = { { name = "Port", value = cfg("mysql_port", 3306), configKey = "mysql_port", def = 3306 } },
  },
  {
    id       = "postgresql",
    label    = "PgSQL",
    category = "development",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "system",
    kind     = "systemd",
    unit     = "postgresql.service",
    ports    = { { name = "Port", value = cfg("postgresql_port", 5432), configKey = "postgresql_port", def = 5432 } },
  },
  {
    id       = "docker",
    label    = "Docker",
    category = "development",
    glyph    = "container",
    glyphOff = "container-off",
    scope    = "system",
    kind     = "systemd",
    unit     = "docker.service",
    ports    = { { name = "Socket", value = "/var/run/docker.sock", configKey = "docker_socket", def = "/var/run/docker.sock" } },
  },
  {
    id       = "seaweedfs",
    label    = "SeaweedFS",
    category = "development",
    glyph    = "server",
    glyphOff = "server-off",
    scope    = "system",
    kind     = "systemd",
    unit     = "seaweedfs.target",
    ports    = {
      { name = "Master", value = cfg("seaweedfs_masterPort", 9333), configKey = "seaweedfs_masterPort", def = 9333 },
      { name = "Volume", value = cfg("seaweedfs_volumePort", 8080), configKey = "seaweedfs_volumePort", def = 8080 },
      { name = "Filer", value = cfg("seaweedfs_filerPort", 8888), configKey = "seaweedfs_filerPort", def = 8888 },
    },
  },
  {
    id       = "mailpit",
    label    = "Mailpit",
    category = "development",
    glyph    = "mail-check",
    glyphOff = "mail-off",
    scope    = "user",
    kind     = "transient",
    unit     = "mailpit.service",
    binary   = cfg("mailpit_binary", "mailpit"),
    autoStart = cfg("mailpit_auto_start", false),
    ports    = {
      { name = "SMTP", value = cfg("mailpit_smtpPort", 1025), configKey = "mailpit_smtpPort", def = 1025 },
      { name = "UI", value = cfg("mailpit_uiPort", 8025), configKey = "mailpit_uiPort", def = 8025 },
    },
    startCmd = function(self)
      return transientStart(self.unit, self.binary,
        "--smtp 127.0.0.1:" .. tostring(self.ports[1].value)
        .. " --listen 127.0.0.1:" .. tostring(self.ports[2].value))
    end,
  },
  {
    id       = "seanime",
    label    = "Seanime",
    category = "entertainment",
    glyph    = "device-desktop",
    glyphOff = "device-desktop-off",
    scope    = "user",
    kind     = "transient",
    unit     = "seanime.service",
    binary   = cfg("seanime_binary", "seanime"),
    autoStart = cfg("seanime_auto_start", false),
    ports    = { { name = "Port", value = cfg("seanime_port", 43211), configKey = "seanime_port", def = 43211 } },
    startCmd = function(self)
      local dir = cfg("seanime_datadir", "$HOME/.local/share/seanime")
      dir = noctalia.expandPath(dir) or dir
      return transientStart(self.unit, self.binary,
        "--datadir " .. dir .. " --port " .. tostring(self.ports[1].value))
    end,
  },
  {
    id       = "stremio",
    label    = "Stremio",
    category = "entertainment",
    glyph    = "movie",
    glyphOff = "video-off",
    scope    = "user",
    kind     = "transient",
    unit     = "stremio.service",
    binary   = cfg("stremio_binary", "stremio-service"),
    autoStart = cfg("stremio_auto_start", false),
    ports    = { { name = "Port", value = cfg("stremio_port", 11470), configKey = "stremio_port", def = 11470 } },
    startCmd = function(self)
      return transientStart(self.unit, self.binary, nil)
    end,
  },
  {
    id       = "warp",
    label    = "WARP",
    category = "tools",
    glyph    = "shield",
    glyphOff = "shield-off",
    scope    = "system",
    kind     = "warp",
    unit     = "cloudflare-warp.service",
    binary   = "warp-cli",
    ports    = nil,
  },
  {
    id       = "waydroid",
    label    = "Waydroid",
    category = "tools",
    glyph    = "device-mobile",
    glyphOff = "device-mobile-off",
    scope    = "system",
    kind     = "waydroid",
    unit     = "waydroid-container.service",
    binary   = "waydroid",
    ports    = nil,
  },
}

M.CATEGORIES = {
  { id = "development", label = "Development" },
  { id = "tools", label = "Tools" },
  { id = "entertainment", label = "Entertainment" },
}

-- Re-read settings (ports, binary, auto-start) in place. Called from the
-- service entry's onConfigChanged so GUI edits apply without a reload.
function M.reloadConfig()
  for _, s in ipairs(M.SERVICES) do
    if s.ports then
      for _, p in ipairs(s.ports) do
        p.value = cfg(p.configKey, p.def)
      end
    end
    if s.binary then
      s.binary = cfg(s.id .. "_binary", s.binary)
    end
    if s.autoStart ~= nil then
      s.autoStart = cfg(s.id .. "_auto_start", false)
    end
  end
end

-- Per-service detail text ---------------------------------------------------

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

function M.detail(service, s)
  local parts = {}

  if s.available == false then
    return "Not installed"
  end

  if service.ports then
    for _, p in ipairs(service.ports) do
      table.insert(parts, p.name .. " " .. tostring(p.value))
    end
  end

  if service.kind == "warp" then
    if s.state == "not-registered" then
      parts = { "Not registered" }
    elseif s.state == "daemon-off" then
      parts = { "Daemon stopped" }
    else
      parts = { "VPN" }
    end
  end

  if service.kind == "waydroid" then
    if s.state == "no-session" then
      parts = { "Container only" }
    elseif s.state == "no-cli" then
      parts = { "CLI missing" }
    else
      parts = { "Android" }
    end
  end

  if s.state == "failed" then
    table.insert(parts, "Status: Failed")
  elseif s.state == "active" or s.state == "connected" then
    local up = fmtDuration(s.sinceSec)
    if up then table.insert(parts, "Up " .. up) end
  elseif s.state == "inactive" or s.state == "daemon-off" or s.state == "disconnected" then
    table.insert(parts, "Stopped")
  elseif s.state == "connecting" or s.state == "disconnecting" then
    table.insert(parts, "Working\u{2026}")
  end

  return table.concat(parts, " \u{00b7} ")
end

function M.find(id)
  for _, s in ipairs(M.SERVICES) do
    if s.id == id then return s end
  end
  return nil
end

M.expandBinary = expandBinary

return M
