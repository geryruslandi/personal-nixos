--!nonstrict
local M = {}

M.PANEL_ID = "gery/ajazz-keyboard:keyboard-panel"

M.EFFECTS = { "off", "static", "breath", "wave", "rainbow" }
M.SCREENS = { "clock", "cpu", "off" }
M.CLOCK_INTERVALS = { 60, 300, 900, 1800, 3600 }
M.STATS_INTERVALS = { 1, 2, 5 }
M.NET_MODES = { "rate", "total" }
M.LANGUAGES = { "en", "zh" }

M.PRESETS = {
  { name = "Blue", color = "#8caaee" },
  { name = "Sky", color = "#99d1db" },
  { name = "Green", color = "#a6d189" },
  { name = "Yellow", color = "#e5c890" },
  { name = "Peach", color = "#ef9f76" },
  { name = "Red", color = "#ea999c" },
  { name = "Mauve", color = "#ca9ee6" },
  { name = "Pink", color = "#f4b8e4" },
  { name = "White", color = "#ffffff" },
}

M.DEFAULTS = {
  effect = "static",
  color = "#89b4fa",
  brightness = 4,
  speed = 2,
  screen = "clock",
  language = "en",
  clock_enabled = true,
  clock_interval_s = 300,
  stats_interval_s = 1,
  disk_path = "/",
  net_mode = "rate",
}

local function clamp_int(value, low, high, fallback)
  value = tonumber(value)
  if value == nil then
    return fallback
  end
  value = math.floor(value + 0.5)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function one_of(value, allowed, fallback)
  for _, candidate in ipairs(allowed) do
    if value == candidate then
      return value
    end
  end
  return fallback
end

function M.normalize_color(value)
  if type(value) ~= "string" then
    return M.DEFAULTS.color
  end
  local hex = value:gsub("#", ""):lower()
  if not hex:match("^%x%x%x%x%x%x$") then
    return M.DEFAULTS.color
  end
  return "#" .. hex
end

function M.normalize_panel(panel)
  panel = type(panel) == "table" and panel or {}
  return {
    effect = one_of(panel.effect, M.EFFECTS, M.DEFAULTS.effect),
    color = M.normalize_color(panel.color),
    brightness = clamp_int(panel.brightness, 0, 4, M.DEFAULTS.brightness),
    speed = clamp_int(panel.speed, 0, 4, M.DEFAULTS.speed),
    screen = one_of(panel.screen, M.SCREENS, M.DEFAULTS.screen),
    language = one_of(panel.language, M.LANGUAGES, M.DEFAULTS.language),
    clock_enabled = panel.clock_enabled ~= false and panel.clock_enabled ~= "false",
    clock_interval_s = clamp_int(panel.clock_interval_s, 30, 86400, M.DEFAULTS.clock_interval_s),
    stats_interval_s = clamp_int(panel.stats_interval_s, 1, 10, M.DEFAULTS.stats_interval_s),
    disk_path = type(panel.disk_path) == "string" and panel.disk_path ~= "" and panel.disk_path or M.DEFAULTS.disk_path,
    net_mode = one_of(panel.net_mode, M.NET_MODES, M.DEFAULTS.net_mode),
  }
end

function M.copy(panel)
  local result = {}
  for key, value in pairs(panel) do
    result[key] = value
  end
  return result
end

function M.merge(panel, patch)
  local result = M.copy(panel)
  if type(patch) == "table" then
    for key, value in pairs(patch) do
      result[key] = value
    end
  end
  return M.normalize_panel(result)
end

function M.hex_to_rgb(value)
  local hex = M.normalize_color(value):sub(2)
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function M.rgb_to_hex(red, green, blue)
  return string.format(
    "#%02x%02x%02x",
    clamp_int(red, 0, 255, 0),
    clamp_int(green, 0, 255, 0),
    clamp_int(blue, 0, 255, 0)
  )
end

function M.data_dir()
  return noctalia.pluginDataDir()
end

function M.panel_path()
  local dir = M.data_dir()
  if dir == nil then
    return nil
  end
  return dir .. "/panel.json"
end

function M.daemon_path()
  local dir = M.data_dir()
  if dir == nil then
    return nil
  end
  return dir .. "/daemon.json"
end

function M.load_panel()
  local path = M.panel_path()
  if path == nil then
    return M.copy(M.DEFAULTS)
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return M.copy(M.DEFAULTS)
  end
  local ok, decoded = pcall(function()
    return noctalia.json.decode(raw)
  end)
  if not ok or type(decoded) ~= "table" then
    return M.copy(M.DEFAULTS)
  end
  return M.normalize_panel(decoded)
end

function M.save_panel(panel)
  local path = M.panel_path()
  if path == nil then
    return false
  end
  local ok, encoded = pcall(function()
    return noctalia.json.encode(M.normalize_panel(panel))
  end)
  if not ok or encoded == nil then
    return false
  end
  return noctalia.writeFile(path, encoded) == true
end

function M.daemon_state(panel, seq)
  return {
    rev = seq.rev or 0,
    clock_seq = seq.clock or 0,
    reconnect_seq = seq.reconnect or 0,
    rgb = {
      effect = panel.effect,
      color = panel.color,
      brightness = panel.brightness,
      speed = panel.speed,
    },
    screen = {
      mode = panel.screen,
      language = panel.language,
    },
    clock = {
      enabled = panel.clock_enabled,
      interval_s = panel.clock_interval_s,
    },
    stats = {
      interval_s = panel.stats_interval_s,
      disk_path = panel.disk_path,
      net_mode = panel.net_mode,
    },
  }
end

function M.write_daemon(panel, seq)
  local path = M.daemon_path()
  if path == nil then
    return false
  end
  local ok, encoded = pcall(function()
    return noctalia.json.encode(
      M.daemon_state(M.normalize_panel(panel), seq)
    )
  end)
  if not ok or encoded == nil then
    return false
  end
  return noctalia.writeFile(path, encoded) == true
end

function M.expand_binary(name, fallback)
  if type(name) ~= "string" or name == "" then
    name = fallback
  end
  local expanded = noctalia.expandPath(name)
  if expanded ~= nil and noctalia.fileExists(expanded) then
    return expanded
  end
  local env_path = noctalia.getenv("PATH") or ""
  for directory in env_path:gmatch("[^:]+") do
    local candidate = directory .. "/" .. name
    if noctalia.fileExists(candidate) then
      return candidate
    end
  end
  if fallback ~= nil and fallback ~= name then
    return M.expand_binary(fallback, nil)
  end
  return name
end

function M.request(action, extra)
  local request = { seq = noctalia.nowMs(), action = action }
  if type(extra) == "table" then
    for key, value in pairs(extra) do
      request[key] = value
    end
  end
  noctalia.state.set("request", request)
end

function M.clamp_int(value, low, high, fallback)
  return clamp_int(value, low, high, fallback)
end

return M
