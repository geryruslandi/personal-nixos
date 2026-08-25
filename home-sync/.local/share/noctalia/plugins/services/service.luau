-- Service entry: polls every service, publishes aggregated state,
-- handles one-shot auto-start per transient service, and executes
-- start/stop requests coming from the panel via noctalia.state.

local services = require("./lib/services.luau")

noctalia.setUpdateInterval(3000)

local state = {}
local bootStarted = {}
local lastReqSeq = 0

for _, s in ipairs(services.SERVICES) do
  state[s.id] = { state = "unknown", available = nil, sinceSec = nil, enabled = "unknown", busy = false }
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

local function publish()
  noctalia.state.set("services", state)
end

local function setState(id, st, patch)
  local s = state[id]
  s.state = st
  if patch then
    if patch.available ~= nil then s.available = patch.available end
    if patch.sinceSec ~= nil then s.sinceSec = patch.sinceSec end
    if patch.enabled ~= nil then s.enabled = patch.enabled end
  end
end

-- systemd poll (system scope: docker/redis/mysql/postgresql/seaweedfs)
local function pollSystemd(service, done)
  local cmd = table.concat({
    "systemctl is-active " .. service.unit,
    "systemctl is-enabled " .. service.unit .. " 2>&1",
    "awk '{print $1}' /proc/uptime",
    "systemctl show " .. service.unit .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local enabledOut = lines[2] or ""
    local available = enabledOut ~= "not-found"
      and not string.find(enabledOut, "No such file or directory", 1, true)
      and not string.find(enabledOut, "Failed to get unit file state", 1, true)
    local sinceSec = nil
    if lines[3] and lines[4] then
      local sysUp = tonumber(lines[3])
      local monoUs = tonumber(lines[4])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    setState(service.id, lines[1] or "unknown", {
      available = available,
      sinceSec = sinceSec,
      enabled = enabledOut,
    })
    publish()
    if done then done() end
  end)
  if not ok then
    setState(service.id, "error", {})
    publish()
    if done then done() end
  end
end

-- systemd poll (user scope: transient seanime/stremio/mailpit)
local function pollTransient(service, done)
  local cmd = table.concat({
    "systemctl --user is-active " .. service.unit,
    "awk '{print $1}' /proc/uptime",
    "systemctl --user show " .. service.unit .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local binary = service.binary
    local available = false
    if string.sub(binary, 1, 1) == "/" then
      available = noctalia.fileExists(binary)
    else
      available = noctalia.commandExists(binary)
    end
    local sinceSec = nil
    if lines[2] and lines[3] then
      local sysUp = tonumber(lines[2])
      local monoUs = tonumber(lines[3])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    setState(service.id, lines[1] or "unknown", {
      available = available,
      sinceSec = sinceSec,
    })
    local st = state[service.id].state
    if not bootStarted[service.id] and service.autoStart and available and st ~= "active" then
      bootStarted[service.id] = true
      startService(service.id)
      if done then done() end
      return
    end
    publish()
    if done then done() end
  end)
  if not ok then
    setState(service.id, "error", {})
    publish()
    if done then done() end
  end
end

-- warp: daemon -> registration -> status chain
local function pollWarpStatus(done)
  local warp = services.find("warp")
  local ok = noctalia.runAsync(services.expandBinary(warp.binary) .. " status", function(res)
    if res and res.exitCode == 0 then
      local out = res.stdout or ""
      if out:find("Connected", 1, true) then
        setState("warp", "connected", { available = true })
      else
        setState("warp", "disconnected", { available = true })
      end
    else
      setState("warp", "disconnected", { available = true })
    end
    publish()
    if done then done() end
  end)
  if not ok then
    setState("warp", "disconnected", { available = true })
    publish()
    if done then done() end
  end
end

local function pollWarpRegistration(done)
  local warp = services.find("warp")
  local ok = noctalia.runAsync(services.expandBinary(warp.binary) .. " registration show", function(res)
    if res and res.exitCode == 0 then
      pollWarpStatus(done)
    else
      setState("warp", "not-registered", { available = true })
      publish()
      if done then done() end
    end
  end)
  if not ok then
    setState("warp", "not-registered", { available = true })
    publish()
    if done then done() end
  end
end

local function pollWarpDaemon(done)
  local warp = services.find("warp")
  local cmd = table.concat({
    "systemctl is-active " .. warp.unit,
    "systemctl is-enabled " .. warp.unit .. " 2>&1",
    "awk '{print $1}' /proc/uptime",
    "systemctl show " .. warp.unit .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local out = lines[1] or ""
    local enabledOut = lines[2] or ""
    local sinceSec = nil
    if lines[3] and lines[4] then
      local sysUp = tonumber(lines[3])
      local monoUs = tonumber(lines[4])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    setState("warp", "unknown", { available = true, sinceSec = sinceSec, enabled = enabledOut })
    if out:match("^active") then
      pollWarpRegistration(done)
    else
      setState("warp", "daemon-off", { available = true, sinceSec = nil })
      publish()
      if done then done() end
    end
  end)
  if not ok then
    setState("warp", "daemon-off", { available = true })
    publish()
    if done then done() end
  end
end

local function pollWarp(done)
  local warp = services.find("warp")
  if not noctalia.commandExists(warp.binary) then
    setState("warp", "no-cli", { available = false })
    publish()
    if done then done() end
    return
  end
  pollWarpDaemon(done)
end

-- waydroid: container -> session status chain
local function pollWaydroidSession(done)
  local ok = noctalia.runAsync(services.expandBinary("waydroid") .. " status", function(res)
    local sessionUp = false
    if res and res.exitCode == 0 then
      local out = res.stdout or ""
      sessionUp = out:find("Session:%s+RUNNING") ~= nil
    end
    setState("waydroid", sessionUp and "active" or "no-session", { available = true })
    publish()
    if done then done() end
  end)
  if not ok then
    setState("waydroid", "no-session", { available = true })
    publish()
    if done then done() end
  end
end

local function pollWaydroidContainer(done)
  local waydroid = services.find("waydroid")
  local cmd = table.concat({
    "systemctl is-active " .. waydroid.unit,
    "systemctl is-enabled " .. waydroid.unit .. " 2>&1",
    "awk '{print $1}' /proc/uptime",
    "systemctl show " .. waydroid.unit .. " -p ActiveEnterTimestampMonotonic --value 2>/dev/null",
  }, "; ")
  local ok = noctalia.runAsync(cmd, function(res)
    local lines = splitLines(res and res.stdout)
    local enabledOut = lines[2] or ""
    local available = enabledOut ~= "not-found"
      and not string.find(enabledOut, "No such file or directory", 1, true)
      and not string.find(enabledOut, "Failed to get unit file state", 1, true)
    local sinceSec = nil
    if lines[3] and lines[4] then
      local sysUp = tonumber(lines[3])
      local monoUs = tonumber(lines[4])
      if sysUp and monoUs and monoUs > 0 then
        sinceSec = sysUp - monoUs / 1000000
      end
    end
    setState("waydroid", "unknown", { available = available, sinceSec = sinceSec, enabled = enabledOut })
    if (lines[1] or ""):match("^active") then
      pollWaydroidSession(done)
    else
      setState("waydroid", "stopped", { available = available, sinceSec = nil })
      publish()
      if done then done() end
    end
  end)
  if not ok then
    setState("waydroid", "stopped", { available = true })
    publish()
    if done then done() end
  end
end

local function pollWaydroid(done)
  if not noctalia.commandExists("waydroid") then
    setState("waydroid", "no-cli", { available = false })
    publish()
    if done then done() end
    return
  end
  pollWaydroidContainer(done)
end

-- start / stop --------------------------------------------------------------
-- Forward declarations (pollTransient / refresh call these before the real
-- definitions below are reached at runtime via callbacks).
local startService = nil
local stopService = nil
local refresh = nil

startService = function(id)
  local service = services.find(id)
  if not service then return end
  local s = state[id]
  if s.busy then return end
  s.busy = true
  publish()

  local cmd
  if service.kind == "warp" then
    local warpCli = services.expandBinary(service.binary)
    cmd = "systemctl start " .. service.unit
      .. " && sleep 1"
      .. " && " .. warpCli .. " registration show >/dev/null 2>&1"
      .. " && for i in 1 2 3 4 5 6 7 8 9 10; do " .. warpCli .. " connect && break; sleep 1; done"
    setState(id, "connecting", {})
  elseif service.kind == "waydroid" then
    cmd = "systemctl start " .. service.unit
      .. " && sleep 3"
      .. " && { systemctl --user reset-failed waydroid-session 2>/dev/null || true; systemctl --user stop waydroid-session 2>/dev/null || true; }"
      .. " && systemd-run --user --unit=waydroid-session --collect --property=Restart=no -- "
      .. services.expandBinary(service.binary) .. " session start"
    setState(id, "connecting", {})
  elseif service.kind == "transient" then
    cmd = service.startCmd(service)
    setState(id, "connecting", {})
  else
    cmd = "systemctl start " .. service.unit
    setState(id, "connecting", {})
  end
  publish()

  local spawned = noctalia.runAsync(cmd, function(res)
    s.busy = false
    if res and res.exitCode ~= 0 then
      noctalia.notify(service.label .. " failed to start", (res.stderr or "") or "systemctl error")
      setState(id, "failed", {})
    end
    publish()
    refresh()
  end)
  if not spawned then
    s.busy = false
    setState(id, "failed", {})
    noctalia.notify(service.label .. " failed to start", "command could not be spawned")
    publish()
    refresh()
  end
end

stopService = function(id)
  local service = services.find(id)
  if not service then return end
  local s = state[id]
  if s.busy then return end
  s.busy = true
  publish()

  local cmd
  if service.kind == "warp" then
    cmd = services.expandBinary(service.binary) .. " disconnect; systemctl stop " .. service.unit
    setState(id, "disconnecting", {})
  elseif service.kind == "waydroid" then
    cmd = services.expandBinary(service.binary) .. " session stop 2>/dev/null"
      .. "; systemctl --user stop waydroid-session 2>/dev/null"
      .. "; systemctl stop " .. service.unit
    setState(id, "disconnecting", {})
  elseif service.kind == "transient" then
    cmd = "systemctl --user stop " .. service.unit
    setState(id, "disconnecting", {})
  else
    cmd = "systemctl stop " .. service.unit
    setState(id, "disconnecting", {})
  end
  publish()

  local spawned = noctalia.runAsync(cmd, function(res)
    s.busy = false
    publish()
    refresh()
  end)
  if not spawned then
    s.busy = false
    publish()
    refresh()
  end
end

-- poll all ------------------------------------------------------------------

-- Sequential sweep: Noctalia drops runAsync spawns beyond a small number of
-- concurrent children (the last service of a simultaneous burst always lost),
-- so polls are chained one at a time via `done` callbacks. A sweep in
-- progress coalesces overlapping requests into one follow-up sweep.
local sweeping = false
local resweep = false
local sweepStartedAt = 0

refresh = function()
  if sweeping then
    resweep = true
    return
  end
  sweeping = true
  resweep = false
  sweepStartedAt = noctalia.nowMs()
  local list = services.SERVICES
  local idx = 0
  local function runNext()
    idx = idx + 1
    local service = list[idx]
    if not service then
      sweeping = false
      if resweep then refresh() end
      return
    end
    if service.kind == "warp" then
      pollWarp(runNext)
    elseif service.kind == "waydroid" then
      pollWaydroid(runNext)
    elseif service.kind == "transient" then
      pollTransient(service, runNext)
    else
      pollSystemd(service, runNext)
    end
  end
  runNext()
end

-- Panel requests toggles through state (sequence number = change detection).
noctalia.state.watch("toggleRequest", function(req)
  if not req or type(req) ~= "table" then return end
  if req.seq == lastReqSeq then return end
  lastReqSeq = req.seq
  local service = services.find(req.id)
  if not service then return end
  if req.action == "start" then
    startService(req.id)
  elseif req.action == "stop" then
    stopService(req.id)
  end
end)

function update()
  -- Watchdog: a stalled sweep (hung child, lost callback) must never wedge
  -- polling permanently; force-reset and let refresh start over.
  if sweeping and noctalia.nowMs() - sweepStartedAt > 10000 then
    sweeping = false
  end
  refresh()
end

function onConfigChanged()
  services.reloadConfig()
  refresh()
end
