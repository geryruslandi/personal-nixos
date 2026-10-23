--!nonstrict
local ak = require("./lib/ak820.luau")

local panel = ak.load_panel()
local seq = { rev = 1, clock = 0, reconnect = 0 }
local status = { connected = false, error = nil }
local last_request = nil
local last_line_ms = noctalia.nowMs()
local daemon_started = false
local last_check = 0
local checking_daemon = false

local function shq(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function publish()
  local snapshot = {}
  for key, value in pairs(status) do
    snapshot[key] = value
  end
  snapshot.panel = panel
  snapshot.rev = seq.rev
  noctalia.state.set("ak820", snapshot)
end

local function persist(bump_rev)
  panel = ak.normalize_panel(panel)
  ak.save_panel(panel)
  if bump_rev then
    seq.rev = seq.rev + 1
  end
  ak.write_daemon(panel, seq)
  publish()
end

local function on_line(line)
  local ok, decoded = pcall(function()
    return noctalia.json.decode(line)
  end)
  if not ok or type(decoded) ~= "table" then
    return
  end
  status = decoded
  last_line_ms = noctalia.nowMs()
  publish()
end

local function start_daemon()
  local state_path = ak.daemon_path()
  if state_path == nil then
    status.connected = false
    status.error = "plugin data directory unavailable"
    publish()
    return
  end
  local binary = ak.expand_binary(noctalia.getConfig("binary") or "ak820ctl", "ak820ctl")
  local available = noctalia.fileExists(binary) or noctalia.commandExists(binary)
  if not available and noctalia.fileExists("/run/current-system/sw/bin/ak820ctl") then
    binary = "/run/current-system/sw/bin/ak820ctl"
    available = true
  end
  if not available then
    status.connected = false
    status.error = "ak820ctl not found"
    noctalia.log("ajazz-keyboard: ak820ctl not found at " .. tostring(binary))
    publish()
    return
  end
  local command = shq(binary) .. " daemon --state " .. shq(state_path)
  local device = noctalia.getConfig("device_path")
  if type(device) == "string" and device ~= "" then
    command = command .. " --device " .. shq(device)
  end
  daemon_started = noctalia.runStream(command, on_line) == true
  last_line_ms = noctalia.nowMs()
  if not daemon_started then
    status.connected = false
    status.error = "failed to start ak820ctl daemon"
    noctalia.log("ajazz-keyboard: failed to start " .. command)
    publish()
  end
end

local function apply(next_panel)
  panel = ak.normalize_panel(next_panel)
  persist(true)
end

local function handle_request(request)
  if type(request) ~= "table" or type(request.seq) ~= "number" then
    return
  end
  if request.seq == last_request then
    return
  end
  last_request = request.seq
  if request.action == "config" then
    apply(request.config)
  elseif request.action == "patch" then
    apply(ak.merge(panel, request.patch))
  elseif request.action == "clock_sync" then
    seq.clock = seq.clock + 1
    ak.write_daemon(panel, seq)
    publish()
  elseif request.action == "reconnect" then
    seq.reconnect = seq.reconnect + 1
    ak.write_daemon(panel, seq)
    publish()
  elseif request.action == "reset" then
    apply(ak.copy(ak.DEFAULTS))
  end
end

ak.save_panel(panel)
ak.write_daemon(panel, seq)
publish()
start_daemon()

noctalia.setUpdateInterval(3000)

function update()
  local now = noctalia.nowMs()
  if daemon_started and now - last_line_ms > 8000 then
    status.connected = false
    status.error = "daemon not responding"
    publish()
  end
  if now - last_check < 10000 or checking_daemon then
    return
  end
  last_check = now
  local state_path = ak.daemon_path()
  if state_path == nil then
    return
  end
  local pgrep = ak.expand_binary("pgrep", "pgrep")
  local pattern = "ak820ctl daemon --state " .. state_path
  checking_daemon = true
  local started = noctalia.runAsync(shq(pgrep) .. " -f " .. shq(pattern), function(result)
    checking_daemon = false
    if result ~= nil and result.exitCode == 1 then
      daemon_started = false
      start_daemon()
    end
  end)
  if not started then
    checking_daemon = false
  end
end

noctalia.state.watch("request", handle_request)
