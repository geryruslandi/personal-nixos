--!nonstrict
-- Sole owner of the Sony headphone daemon for gery/sony-headset. Launches
-- sonyd (via systemd-run --user), forwards widget/panel requests to the
-- sonyctl CLI, and republishes the daemon's status.json through noctalia.state.

local sony = require("./lib/sony.luau")

local data = nil

local function publish()
  noctalia.state.set("headset", data)
end

local function readState()
  local raw = noctalia.readFile(sony.stateFile())
  if raw == nil or raw == "" then
    data = nil
    return
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) == "table" then
    decoded.updated_at = noctalia.nowMs()
    data = decoded
  end
end

local function refresh()
  readState()
  publish()
end

-- Daemon lifecycle -------------------------------------------------------

local function startDaemon(force)
  noctalia.mkdirAll(sony.baseDir())
  if not force and noctalia.fileExists(sony.socketFile()) then
    return
  end
  noctalia.runAsync(sony.daemonCommand(), function(res)
    if res and res.exitCode ~= 0 and res.stderr ~= "" then
      noctalia.log("sony-headset: daemon start: " .. tostring(res.stderr))
    end
  end)
end

-- Requests from the widget/panel ----------------------------------------

local lastReqSeq = 0

noctalia.state.watch("request", function(req)
  if type(req) ~= "table" or type(req.seq) ~= "number" then
    return
  end
  if req.seq <= lastReqSeq then
    return
  end
  lastReqSeq = req.seq
  local argv = sony.actionArgv(req)
  if argv == nil then
    return
  end
  noctalia.runAsync(argv, function(_)
    refresh()
  end)
end)

-- Lifecycle --------------------------------------------------------------

function update()
  noctalia.setUpdateInterval((tonumber(sony.cfg("refresh_seconds", 15)) or 15) * 1000)
  refresh()
end

function onConfigChanged()
  startDaemon(true)
  refresh()
end

function onExit()
  -- leave the daemon running: it is idle-managed and survives plugin reloads;
  -- stopping it here would drop the Bluetooth link on every reload.
end

startDaemon(false)
noctalia.setUpdateInterval((tonumber(sony.cfg("refresh_seconds", 15)) or 15) * 1000)
refresh()
