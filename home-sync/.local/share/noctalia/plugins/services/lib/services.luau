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

-- Shell-quote a single value for interpolation into a start command line.
local function shq(v)
  v = tostring(v)
  return "'" .. v:gsub("'", "'\\''") .. "'"
end

-- Shared start command builders --------------------------------------------

-- systemd-run transient user unit (plugin-owned services)
-- NOTE: plain concat — the systemd-run invocation is ONE shell statement;
-- joining its option lines with "; " would execute them as separate commands.
local function transientStart(unit, bin, args)
  return "systemctl --user reset-failed " .. unit .. " 2>/dev/null"
    .. "; systemd-run --user --unit=" .. unit:gsub("%.service$", "") .. " --collect"
    .. " --property=Restart=on-failure --property=RestartSec=3"
    .. " -- " .. expandBinary(bin) .. (args and (" " .. args) or "")
end

-- Start an existing HM-declared user unit (docker rootless daemon, sonarqube
-- stack); the plugin only front-ends `systemctl --user`. `env` carries the
-- plugin settings these units consume (e.g. SONARQUBE_WEB_PORT baked at
-- generation time by HM — pass nil for build-time fixed values).
local function unitStart(unit)
  -- --no-block: queue the start job and return immediately. Noctalia's
  -- runAsync kills commands after 5s, and a synchronous start can block
  -- >5s (e.g. a previous unit still shutting down gracefully). The job
  -- itself would keep running in systemd and complete, but the killed
  -- client triggers a false "failed to start" notification. Polling
  -- (3s) reflects the real progress instead.
  return "systemctl --user start --no-block " .. unit
end

-- Split a comma/space separated list into space separated (for wrappers that
-- expect one argument carrying multiple values after validation).
local function listArg(raw, def)
  if raw == nil or raw == "" then raw = def end
  return tostring(raw):gsub("[,;]+", " ")
end

-- Registry ------------------------------------------------------------------

M.SERVICES = {
  {
    -- Fully plugin-owned: real args on the start line (wrapper).
    id       = "redis",
    label    = "Redis",
    category = "databases",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "user",
    kind     = "transient",
    unit     = "redis.service",
    binary   = cfg("redis_binary", "~/.config/gery-dev-scripts/gery-redis-dev"),
    autoStart = cfg("redis_auto_start", false),
    blurb    = "Cache store",
    ports    = {
      { name = "Port", value = cfg("redis_port", 6379), configKey = "redis_port", def = 6379 },
    },
    startCmd = function(self)
      return transientStart(self.unit, self.binary,
        "--port " .. shq(self.ports[1].value)
        .. (cfg("redis_password", "") ~= "" and (" --password " .. shq(cfg("redis_password", ""))) or ""))
    end,
  },
  {
    id       = "mysql",
    label    = "MySQL",
    category = "databases",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "user",
    kind     = "transient",
    unit     = "mysql.service",
    binary   = cfg("mysql_binary", "~/.config/gery-dev-scripts/gery-mysql-dev"),
    autoStart = cfg("mysql_auto_start", false),
    blurb    = "MySQL DB",
    ports    = {
      { name = "Port", value = cfg("mysql_port", 3306), configKey = "mysql_port", def = 3306 },
      { name = "DBs", value = cfg("mysql_databases", ""), configKey = "mysql_databases", def = "" },
    },
    startCmd = function(self)
      local args = "--port " .. shq(self.ports[1].value)
        .. " --user " .. shq(cfg("mysql_user", "root"))
        .. (cfg("mysql_password", "") ~= "" and (" --password " .. shq(cfg("mysql_password", ""))) or "")
        .. (self.ports[2].value ~= "" and (" --databases " .. shq(listArg(self.ports[2].value, ""))) or "")
      return transientStart(self.unit, self.binary, args)
    end,
  },
  {
    id       = "postgresql",
    label    = "PgSQL",
    category = "databases",
    glyph    = "database",
    glyphOff = "database-off",
    scope    = "user",
    kind     = "transient",
    unit     = "postgresql.service",
    binary   = cfg("postgres_binary", "~/.config/gery-dev-scripts/gery-pg-dev"),
    autoStart = cfg("postgres_auto_start", false),
    blurb    = "Postgres DB",
    ports    = {
      { name = "Port", value = cfg("postgres_port", 5432), configKey = "postgres_port", def = 5432 },
      { name = "DBs", value = cfg("postgres_databases", "postgres"), configKey = "postgres_databases", def = "postgres" },
    },
    startCmd = function(self)
      local args = "--port " .. shq(self.ports[1].value)
        .. " --user " .. shq(cfg("postgres_user", "postgres"))
        .. (cfg("postgres_password", "") ~= "" and (" --password " .. shq(cfg("postgres_password", ""))) or "")
        .. (self.ports[2].value ~= "" and (" --databases " .. shq(listArg(self.ports[2].value, "postgres"))) or "")
      return transientStart(self.unit, self.binary, args)
    end,
  },
  {
    -- User-level rootless daemon unit (HM-generated): the plugin toggles
    -- `systemctl --user` and nothing else; no config keys do anything here.
    id       = "docker",
    label    = "Docker",
    category = "development",
    glyph    = "container",
    glyphOff = "container-off",
    scope    = "user",
    kind     = "transient",
    unit     = "docker.service",
    binary   = "docker",
    fixedBinary = true,
    autoStart = cfg("docker_auto_start", false),
    blurb    = "Container daemon",
    ports    = nil,
    startCmd = function(self) return unitStart(self.unit) end,
  },
  {
    -- SonarQube stack as user-level containers (HM-generated compose + a
    -- provision/attach wrapper). The Web port is REAL: it is passed as
    -- SONARQUBE_WEB_PORT into the wrapper's docker compose interpolation.
    id       = "sonarqube",
    label    = "SonarQube",
    category = "development",
    glyph    = "bug",
    glyphOff = "bug-off",
    scope    = "user",
    kind     = "transient",
    unit     = "sonarqube.service",
    binary   = cfg("sonarqube_binary", "~/.config/gery-dev-scripts/gery-sonarqube-dev"),
    autoStart = cfg("sonarqube_auto_start", false),
    blurb    = "Code quality",
    ports    = {
      { name = "Web", value = cfg("sonarqube_webPort", 9000), configKey = "sonarqube_webPort", def = 9000 },
    },
    startCmd = function(self)
      return transientStart(self.unit, self.binary, "--port " .. shq(self.ports[1].value))
    end,
  },
  {
    id       = "seaweedfs",
    -- Fully plugin-owned: dims/datadir/ports all real settings (wrapper).
    label    = "SeaweedFS",
    category = "development",
    glyph    = "server",
    glyphOff = "server-off",
    scope    = "user",
    kind     = "transient",
    unit     = "seaweedfs.service",
    binary   = cfg("seaweedfs_binary", "~/.config/gery-dev-scripts/gery-seaweed-dev"),
    autoStart = cfg("seaweedfs_auto_start", false),
    blurb    = "Object storage",
    ports    = {
      { name = "Master", value = cfg("seaweedfs_masterPort", 9333), configKey = "seaweedfs_masterPort", def = 9333 },
      { name = "Volume", value = cfg("seaweedfs_volumePort", 8080), configKey = "seaweedfs_volumePort", def = 8080 },
      { name = "Filer", value = cfg("seaweedfs_filerPort", 8888), configKey = "seaweedfs_filerPort", def = 8888 },
      { name = "Dir", value = cfg("seaweedfs_datadir", "~/.local/state/seaweedfs"), configKey = "seaweedfs_datadir", def = "~/.local/state/seaweedfs" },
    },
    startCmd = function(self)
      return transientStart(self.unit, self.binary,
        "--datadir " .. shq(self.ports[4].value)
        .. " --bind-ip " .. shq(cfg("seaweedfs_bindIp", "127.0.0.1"))
        .. " --master-port " .. shq(self.ports[1].value)
        .. " --volume-port " .. shq(self.ports[2].value)
        .. " --filer-port " .. shq(self.ports[3].value))
    end,
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
    blurb    = "Dev mail",
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
    id       = "otel",
    label    = "Open Telemetry",
    category = "development",
    glyph    = "route",
    glyphOff = "route-off",
    scope    = "user",
    kind     = "transient",
    unit     = "otel-stack.target",
    binary   = "otelcol-contrib",
    autoStart = cfg("otel_auto_start", false),
    blurb    = "Observability",
    -- Display-only ports: real listeners are fixed in home-modules/otel.nix
    -- (internal Tempo receivers sit on 14317/14318). Changing these keys only
    -- changes what the panel shows.
    ports = {
      { name = "Grafana", value = cfg("otel_grafanaPort", 3000), configKey = "otel_grafanaPort", def = 3000 },
      { name = "OTLP", value = cfg("otel_otlpGrpcPort", 4317), configKey = "otel_otlpGrpcPort", def = 4317 },
      { name = "Tempo", value = cfg("otel_tempoPort", 3200), configKey = "otel_tempoPort", def = 3200 },
    },
    startCmd = function(self)
      -- --no-block: queue the start job and return immediately. Noctalia's
      -- runAsync kills commands after 5s, and a synchronous start can block
      -- >5s (e.g. a previous unit still shutting down gracefully). The job
      -- itself would keep running in systemd and complete, but the killed
      -- client triggers a false "failed to start" notification. Polling
      -- (3s) reflects the real progress instead.
      return "systemctl --user start --no-block " .. self.unit
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
    blurb    = "Media server",
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
    blurb    = "Streaming",
    -- No port setting: stremio-service reads its own config; the plugin passes
    -- no CLI args, so a port setting here would be display-only.
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
    blurb    = "VPN",
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
    blurb    = "Android",
    ports    = nil,
  },
}

M.CATEGORIES = {
  { id = "development", label = "Development" },
  { id = "databases", label = "Databases" },
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
      -- Only re-read declared settings: docker's binary is fixed ("docker"),
      -- and an undeclared `docker_binary` key would log a loud warning.
      if s.fixedBinary ~= true then
        s.binary = cfg(s.id .. "_binary", s.binary)
      end
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
      parts = { "Session down" }
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
  elseif s.state == "connecting" or s.state == "activating" then
    table.insert(parts, "Booting\u{2026}")
  elseif s.state == "disconnecting" or s.state == "deactivating" then
    table.insert(parts, "Stopping\u{2026}")
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
