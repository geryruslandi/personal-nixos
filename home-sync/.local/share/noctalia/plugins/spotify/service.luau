--!nonstrict
-- Sole owner of the Spotify / playerctl / cava subprocesses for gery/spotify.
-- Polls the configured MPRIS player's status+metadata+position, drives the
-- transport commands, fetches time-synced lyrics from lrclib, and runs the
-- cava visualizer stream (only while the widget is in visualizer mode AND
-- Spotify is playing). The widget only reads noctalia.state.

local sp = require("./lib/spotify.luau")

-- Published to the widget. `active` = a matching MPRIS player exists.
local data = { active = false, playing = false, title = "", artist = "", status = "Stopped" }
local hasError = false

local function publish()
  noctalia.state.set("spotify", data)
  noctalia.state.set("error", hasError)
end

-- ── Lyrics ────────────────────────────────────────────────────────────────────

local lyricsEnabled = true
local lastPosition = 0
local updateLyric -- forward declaration
local cache = {} -- trackid -> { lrc = list|nil, plain = string|nil, first = string|nil }
local current = { trackid = nil, lrc = nil, plain = nil, plainFull = nil, loading = false }
local lyric = nil -- { text = string, synced = bool, index = number|nil } | nil
-- Last non-empty line we showed; kept across instrumental gaps and track
-- changes so the capsule never falls back to a placeholder between lines
-- ("show the previous lyric until it changes").
local lastLyricText = nil

local function publishLyric()
  noctalia.state.set("lyric", lyric)
end

-- Full lyrics for the launcher provider (/sp lyric).
local function publishLyrics()
  noctalia.state.set("lyrics", {
    synced = current.lrc,
    plain = current.plainFull,
  })
end

local function resetLyrics()
  current = { trackid = nil, lrc = nil, plain = nil, plainFull = nil, loading = false }
  publishLyrics()
end

updateLyric = function(position)
  lastPosition = position
  if not lyricsEnabled then
    lyric = nil
    publishLyric()
    return
  end
  if current.lrc ~= nil then
    local entry, index = sp.currentLine(current.lrc, position)
    if entry ~= nil and entry.text ~= "" then
      lastLyricText = entry.text
    end
    local text = lastLyricText or sp.firstLineText(current.lrc)
    lyric = { text = text or "♪", synced = true, index = index }
  elseif current.plain ~= nil then
    lastLyricText = current.plain
    lyric = { text = current.plain, synced = false, index = nil }
  elseif lastLyricText ~= nil then
    lyric = { text = lastLyricText, synced = false, index = nil }
  else
    lyric = nil
  end
  publishLyric()
end

-- lrclib is flaky (intermittent 503s), so a miss is retried after this backoff
-- instead of being cached as "no lyrics" for the rest of the track.
local RETRY_MS = 10000

local function parseEntry(decoded)
  local entry = { lrc = nil, plain = nil, first = nil }
  if type(decoded) == "table" then
    if type(decoded.syncedLyrics) == "string" and decoded.syncedLyrics ~= "" then
      entry.lrc = sp.parseLrc(decoded.syncedLyrics)
    elseif type(decoded.plainLyrics) == "string" and decoded.plainLyrics ~= "" then
      entry.plain = decoded.plainLyrics
      entry.first = sp.firstPlainLine(decoded.plainLyrics)
    end
  end
  return entry
end

local function entryHasLyrics(entry)
  return entry ~= nil and (entry.lrc ~= nil or entry.plain ~= nil)
end

local function scheduleRetry()
  current.loading = false
  current.failed = true
  current.retryAt = noctalia.nowMs() + RETRY_MS
end

-- Commit a fetch result. Successful results are cached; empty/failed ones are
-- left uncached (and retried later) so one bad response doesn't strand the
-- track without lyrics. After MAX_ATTEMPTS we accept the miss and stop retrying.
local MAX_ATTEMPTS = 6

local function applyEntry(trackid, entry)
  if current.trackid ~= trackid then
    return -- track changed while the request was in flight
  end
  if entryHasLyrics(entry) then
    cache[trackid] = entry
    current.loading = false
    current.failed = false
    current.lrc = entry.lrc
    current.plain = entry.first
    current.plainFull = entry.plain
    publishLyrics()
    updateLyric(lastPosition)
  elseif (current.attempts or 0) >= MAX_ATTEMPTS then
    cache[trackid] = { lrc = nil, plain = nil, first = nil }
    current.loading = false
    current.failed = false
    publishLyrics()
  else
    scheduleRetry()
    publishLyrics()
  end
end

local fetchSearch -- forward declaration

local function fetchGet(trackid, title, artist, album, duration)
  local started = noctalia.http({
    url = sp.lrclibUrl(title, artist, album, duration),
    headers = { "Accept: application/json", "User-Agent: gery-spotify-noctalia/1.0" },
  }, function(resp)
    if current.trackid ~= trackid then
      return
    end
    local entry = { lrc = nil, plain = nil, first = nil }
    if resp ~= nil and resp.ok and resp.status == 200 then
      entry = parseEntry(noctalia.json.decode(resp.body or ""))
    end
    if entryHasLyrics(entry) then
      applyEntry(trackid, entry)
    else
      fetchSearch(trackid, title, artist) -- /api/get missed; broaden the match
    end
  end)
  if not started then
    scheduleRetry()
  end
end

-- Fallback for when /api/get finds no exact match: /api/search tolerates loose
-- title/artist/album/duration. Prefer the first candidate with synced lyrics.
fetchSearch = function(trackid, title, artist)
  local started = noctalia.http({
    url = sp.lrclibSearchUrl(title, artist),
    headers = { "Accept: application/json", "User-Agent: gery-spotify-noctalia/1.0" },
  }, function(resp)
    if current.trackid ~= trackid then
      return
    end
    local best = nil
    if resp ~= nil and resp.ok and resp.status == 200 then
      local list = noctalia.json.decode(resp.body or "")
      if type(list) == "table" then
        for _, cand in ipairs(list) do
          local e = parseEntry(cand)
          if e.lrc ~= nil then
            best = e
            break
          end
          if best == nil and entryHasLyrics(e) then
            best = e
          end
        end
      end
    end
    applyEntry(trackid, best)
  end)
  if not started then
    scheduleRetry()
  end
end

local function requestLyrics(trackid, title, artist, album, duration)
  if not lyricsEnabled then
    return
  end
  if trackid == nil or trackid == "" or title == "" then
    return
  end
  if trackid == current.trackid then
    -- Retry a previous failure once the backoff has elapsed.
    if current.failed and not current.loading and noctalia.nowMs() >= (current.retryAt or 0) then
      current.loading = true
      current.failed = false
      current.attempts = (current.attempts or 0) + 1
      fetchGet(trackid, title, artist, album, duration)
    end
    return
  end
  local cached = cache[trackid]
  if cached ~= nil then
    current = {
      trackid = trackid,
      lrc = cached.lrc,
      plain = cached.first,
      plainFull = cached.plain,
      loading = false,
      failed = false,
    }
    publishLyrics()
    return
  end
  current = { trackid = trackid, lrc = nil, plain = nil, plainFull = nil, loading = true, failed = false, attempts = 1 }
  publishLyrics()
  fetchGet(trackid, title, artist, album, duration)
end

-- ── cava visualizer ───────────────────────────────────────────────────────────

local viz = {} -- latest cava frame, 0..1 values
local ctrlPath = nil
local cavaAvailable = false
local wantViz = false

local function publishViz()
  noctalia.state.set("viz", viz)
end

local function gateCava()
  if ctrlPath == nil then
    return
  end
  local on = cavaAvailable and wantViz and data.playing == true
  noctalia.writeFile(ctrlPath, on and "1" or "0")
end

-- One persistent runStream child (runStream has no stop API); it starts/stops
-- cava based on the control file we write in gateCava().
local function startRunner()
  local dir = noctalia.pluginDir()
  local base = noctalia.pluginDataDir()
  if dir == nil or base == nil then
    return
  end
  local cava = sp.expandBinary(sp.cfg("cava_binary", "cava"), "cava")
  if not (noctalia.fileExists(cava) or noctalia.commandExists(cava)) then
    noctalia.log("spotify: cava not found; visualizer disabled")
    return
  end
  local conf = dir .. "/cava.conf"
  if not noctalia.fileExists(conf) then
    noctalia.log("spotify: cava.conf missing; visualizer disabled")
    return
  end
  ctrlPath = base .. "/cava.on"
  noctalia.writeFile(ctrlPath, "0")
  -- Noctalia 5.2.1's runStream takes a shell string (unlike runAsync, which
  -- also accepts argv tables), so quote the arguments ourselves.
  local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
  end
  local cmd = table.concat({
    shq(sp.expandBinary("sh", "/bin/sh")),
    shq(dir .. "/cava-runner.sh"),
    shq(cava),
    shq(conf),
    shq(ctrlPath),
    shq(noctalia.getenv("PATH") or ""),
  }, " ")
  local started = noctalia.runStream(cmd, function(line)
    local values = sp.parseCava(line)
    if #values > 0 then
      viz = values
      publishViz()
    end
  end)
  cavaAvailable = started == true
  if not cavaAvailable then
    noctalia.log("spotify: failed to start the cava runner")
  end
end

-- ── Polling ───────────────────────────────────────────────────────────────────

local inFlight = false
local pending = false
local lastStart = 0
local busy = false
local MIN_GAP_MS = 300

local refresh -- forward declaration

local function pollIntervalMs()
  -- synced lyrics need a tighter poll so the 0.5s lead stays meaningful
  if current.lrc ~= nil then
    return 500
  end
  -- fast while the visualizer needs fresh position
  if cavaAvailable and wantViz then
    return 1000
  end
  local secs = tonumber(sp.cfg("refresh_seconds", 2)) or 2
  if secs < 1 then
    secs = 1
  end
  return math.floor(secs * 1000)
end

local function noPlayer()
  data = { active = false, playing = false, title = "", artist = "", status = "Stopped" }
end

local function applyResult(result)
  if result == nil or result.timedOut then
    hasError = true
    noPlayer()
    resetLyrics()
    gateCava()
    return
  end
  if result.exitCode ~= 0 then
    -- no matching player (playerctl exits 1); 127 = playerctl missing
    hasError = result.exitCode == 127
    noPlayer()
    resetLyrics()
    gateCava()
    return
  end
  hasError = false
  local f = sp.splitTab(tostring(result.stdout or ""))
  local status = sp.trim(f[1] or "")
  local title = sp.trim(f[2] or "")
  local artist = sp.trim(f[3] or "")
  local album = sp.trim(f[4] or "")
  local length = tonumber(f[5] or "") or 0
  local position = tonumber(f[6] or "") or 0
  local trackid = sp.trim(f[7] or "")
  data = {
    active = true,
    playing = status == "Playing",
    title = title,
    artist = artist,
    status = status ~= "" and status or "Stopped",
  }
  requestLyrics(trackid, title, artist, album, length / 1000000)
  updateLyric(position / 1000000)
  gateCava()
end

refresh = function()
  if inFlight or busy then
    pending = true
    return
  end
  local now = noctalia.nowMs()
  if MIN_GAP_MS - (now - lastStart) > 0 then
    pending = true
    return
  end
  lastStart = now
  pending = false
  inFlight = true

  local started = noctalia.runAsync(
    sp.playerctlArgv({
      "metadata",
      "--format",
      "{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{mpris:length}}\t{{position}}\t{{mpris:trackid}}",
    }),
    function(result)
      inFlight = false
      applyResult(result)
      publish()
      if pending then
        refresh()
      end
    end,
    10000
  )

  if not started then
    inFlight = false
    pending = false
    hasError = true
    noPlayer()
    resetLyrics()
    gateCava()
    publish()
  end
end

-- ── Transport commands ────────────────────────────────────────────────────────

local function runCommand(args)
  if busy then
    return
  end
  busy = true
  local started = noctalia.runAsync(sp.playerctlArgv(args), function(_)
    busy = false
    refresh()
  end, 8000)
  if not started then
    busy = false
    noctalia.notify(noctalia.tr("ui.error.command"), noctalia.tr("ui.error.spawn"))
  end
end

-- ── Launch / focus ────────────────────────────────────────────────────────────

local function launch()
  local bin = sp.expandBinary(sp.cfg("spotify_binary", "spotify"), "spotify")
  noctalia.runAsync({ bin })
  lastStart = 0
  refresh()
end

-- ── Requests from the widget ──────────────────────────────────────────────────

local lastReqSeq = 0

noctalia.state.watch("request", function(req)
  if type(req) ~= "table" then
    return
  end
  if type(req.seq) ~= "number" or req.seq <= lastReqSeq then
    return
  end
  lastReqSeq = req.seq
  local action = req.action
  if action == "refresh" then
    refresh()
  elseif action == "mode" then
    wantViz = req.mode == "viz"
    gateCava()
    noctalia.setUpdateInterval(pollIntervalMs())
    refresh()
  elseif action == "launch" then
    launch()
  elseif action == "toggle" then
    runCommand({ "play-pause" })
  elseif action == "next" then
    runCommand({ "next" })
  elseif action == "previous" then
    runCommand({ "previous" })
  elseif action == "seek" and tonumber(req.position) then
    runCommand({ "position", tostring(tonumber(req.position)) })
  end
end)

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function update()
  -- Reconcile the widget's mode (covers the load-order race where the widget
  -- publishes its mode before this service registers its request watcher).
  local m = noctalia.state.get("uiMode")
  if type(m) == "string" then
    local v = m == "viz"
    if v ~= wantViz then
      wantViz = v
      gateCava()
    end
  end

  if inFlight and noctalia.nowMs() - lastStart > 12000 then
    inFlight = false
  end
  if inFlight then
    return
  end
  noctalia.setUpdateInterval(pollIntervalMs())
  refresh()
end

function onConfigChanged()
  lyricsEnabled = sp.cfg("lyrics_enabled", true) == true
  noctalia.setUpdateInterval(pollIntervalMs())
  refresh()
end

lyricsEnabled = sp.cfg("lyrics_enabled", true) == true
startRunner()
noctalia.setUpdateInterval(pollIntervalMs())
publish()
publishViz()
publishLyric()
refresh()
