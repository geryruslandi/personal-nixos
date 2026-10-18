--!nonstrict
-- Shared helpers for the gery/spotify plugin: setting reads, subprocess binary
-- resolution, the playerctl argv builder and the MPRIS metadata parser. Required
-- by the service and the widget so they cannot disagree on screen. Needs
-- plugin_api 22 (require) and 24 (argv tables for runAsync).

local M = {}

M.COLOR = {
  ok    = "#4ade80",
  error = "#f87171",
  muted = "on_surface_variant",
}

function M.cfg(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v
end

function M.trim(s)
  return noctalia.string.trim(tostring(s or ""))
end

-- Resolve a bare name to an absolute path. The plugin subprocess does not
-- reliably inherit the session PATH (a bare name fails with "command not
-- found"), so walk the session PATH ourselves. Absolute paths and ~ paths are
-- honoured as-is for a hard override. `fallback` is returned when the setting is
-- empty and nothing was found.
function M.expandBinary(binary, fallback)
  binary = M.trim(binary)
  if binary == "" then return fallback end
  if binary:sub(1, 1) == "/" then return binary end
  local asPath = noctalia.expandPath(binary)
  if asPath and noctalia.fileExists(asPath) then return asPath end
  local envPath = noctalia.getenv("PATH") or ""
  for dir in (envPath .. ":"):gmatch("([^:]*):") do
    if #dir > 0 then
      local candidate = dir .. "/" .. binary
      if noctalia.fileExists(candidate) then return candidate end
    end
  end
  return binary
end

-- Full argv for a playerctl invocation scoped to the configured player.
function M.playerctlArgv(args)
  local out = {
    M.expandBinary(M.cfg("playerctl_binary", "playerctl"), "playerctl"),
    "--player=" .. tostring(M.cfg("player_name", "spotify")),
  }
  for _, a in ipairs(args) do out[#out + 1] = a end
  return out
end

-- Split on tab characters. `gmatch` with a trailing separator yields one field
-- per tab, so "a\tb\t\tc" -> { "a", "b", "", "c" }.
function M.splitTab(s)
  local out = {}
  for field in (tostring(s or "") .. "\t"):gmatch("([^\t]*)\t") do
    out[#out + 1] = field
  end
  return out
end

-- ── Visualizer (cava) ───────────────────────────────────────────────────────

-- cava `data_format = ascii` emits one frame per line: integer bar heights
-- 0..100 separated by ';'. Returns an array of 0..1 values.
function M.parseCava(line)
  local out = {}
  for tok in tostring(line or ""):gmatch("(%d+)") do
    out[#out + 1] = math.min(1, tonumber(tok) / 100)
  end
  return out
end

-- ── Lyrics (lrclib) ─────────────────────────────────────────────────────────

-- Percent-encoded lrclib /api/get URL. Duration (seconds) sharpens the match.
function M.lrclibUrl(title, artist, album, duration)
  local q = function(s)
    return noctalia.string.urlEncode(tostring(s or ""))
  end
  local url = "https://lrclib.net/api/get?track_name="
    .. q(title)
    .. "&artist_name="
    .. q(artist)
  if album ~= nil and album ~= "" then
    url = url .. "&album_name=" .. q(album)
  end
  if type(duration) == "number" and duration > 0 then
    url = url .. "&duration=" .. tostring(math.floor(duration))
  end
  return url
end

-- Parse LRC ("[mm:ss.xx] text", possibly several timestamps per line) into a
-- time-sorted array of { t = seconds, text = string }.
function M.parseLrc(text)
  local out = {}
  for raw in tostring(text or ""):gmatch("[^\n]+") do
    local times = {}
    for mm, ss, frac in raw:gmatch("%[(%d+):(%d+)%.?(%d*)%]") do
      local t = tonumber(mm) * 60 + tonumber(ss)
      if frac ~= "" then
        t = t + tonumber(frac) / (10 ^ #frac)
      end
      times[#times + 1] = t
    end
    local label = raw:gsub("%[%d+:%d+%.?%d*%]", ""):match("^%s*(.-)%s*$") or ""
    for _, t in ipairs(times) do
      out[#out + 1] = { t = t, text = label }
    end
  end
  table.sort(out, function(a, b)
    return a.t < b.t
  end)
  return out
end

-- Show each lyric line this many seconds before its timestamp (perceived
-- latency of the client + our poll interval), so it feels in sync.
M.LYRIC_LEAD = 0.5

-- Last lyric whose timestamp has passed (plus the lead). `lrc` must be sorted.
function M.currentLine(lrc, position)
  if type(lrc) ~= "table" then
    return nil
  end
  local best = nil
  for _, entry in ipairs(lrc) do
    if entry.t <= position + M.LYRIC_LEAD then
      best = entry
    else
      break
    end
  end
  return best
end

-- First non-empty line of unsynced ("plain") lyrics.
function M.firstPlainLine(plain)
  for line in tostring(plain or ""):gmatch("[^\n]+") do
    local t = M.trim(line)
    if t ~= "" then
      return t
    end
  end
  return nil
end

return M
