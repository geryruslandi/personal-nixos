--!nonstrict
-- Sole owner of the XM5 control daemon for gery/xm5. Launches xm5d (via
-- systemd-run --user), forwards widget/panel requests to the xm5ctl CLI, and
-- republishes the daemon's status.json through noctalia.state.

local xm5 = require("./lib/xm5.luau")

local data = nil

local function publish()
  noctalia.state.set("xm5", data)
end

local function readState()
  local raw = noctalia.readFile(xm5.stateFile())
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
  noctalia.mkdirAll(xm5.baseDir())
  if not force and noctalia.fileExists(xm5.socketFile()) then
    return
  end
  local cmd = xm5.daemonCommand()
  if force then
    cmd = "systemctl --user stop xm5d 2>/dev/null; " .. cmd
  end
  noctalia.runAsync(cmd, function(res)
    if res and res.exitCode ~= 0 and res.stderr ~= "" then
      noctalia.log("xm5: daemon start: " .. tostring(res.stderr))
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
  local argv = xm5.actionArgv(req)
  if argv == nil then
    return
  end
  noctalia.runAsync(argv, function(_)
    refresh()
  end)
end)

-- Lifecycle --------------------------------------------------------------

function update()
  noctalia.setUpdateInterval((tonumber(xm5.cfg("refresh_seconds", 15)) or 15) * 1000)
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
noctalia.setUpdateInterval((tonumber(xm5.cfg("refresh_seconds", 15)) or 15) * 1000)
refresh()
