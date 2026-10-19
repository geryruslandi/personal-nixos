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

local function startDaemon()
  noctalia.runAsync(sony.daemonCommand(), function(res)
    if res and res.exitCode ~= 0 and res.stderr ~= "" then
      noctalia.log("sony-headset: daemon start: " .. tostring(res.stderr))
    end
  end)
end

-- Start the daemon only when it is not already active. A stale control.sock
-- (left behind after a logout/suspend) must never make us skip the start.
local function ensureDaemon()
  noctalia.mkdirAll(sony.baseDir())
  local systemctl = sony.expandBinary("systemctl")
  noctalia.runAsync({ systemctl, "--user", "is-active", "sonyd" }, function(res)
    local state = res and (res.stdout or ""):gsub("%s+$", "") or ""
    if res ~= nil and res.exitCode == 0 and state == "active" then
      return
    end
    startDaemon()
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
  ensureDaemon()
  refresh()
end

function onConfigChanged()
  -- restart unconditionally so new settings (address/channel/...) take effect
  startDaemon()
  refresh()
end

function onExit()
  -- leave the daemon running: it is idle-managed and survives plugin reloads;
  -- stopping it here would drop the Bluetooth link on every reload.
end

ensureDaemon()
noctalia.setUpdateInterval((tonumber(sony.cfg("refresh_seconds", 15)) or 15) * 1000)
refresh()
