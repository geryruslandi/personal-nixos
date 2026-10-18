-- Shared helpers for the gery/xm5 plugin (Sony WH-1000XM5 control).
-- Single source of truth for settings, colours/glyphs, argv construction and
-- subprocess binary resolution.

local M = {}

-- Settings ---------------------------------------------------------------

function M.cfg(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then
    return default
  end
  return v
end

function M.baseDir()
  return noctalia.expandPath(M.cfg("state_dir", "~/.local/state/noctalia-xm5"))
end

function M.stateFile()
  return M.baseDir() .. "/status.json"
end

function M.socketFile()
  return M.baseDir() .. "/control.sock"
end

-- Resolve a bare binary name to an absolute path. Plugin subprocesses do not
-- inherit the session PATH, so bare names fail without this.
function M.expandBinary(binary)
  if string.sub(binary, 1, 1) == "/" then
    return binary
  end
  local path = noctalia.expandPath(binary)
  if path and noctalia.fileExists(path) then
    return path
  end
  local envPath = noctalia.getenv("PATH") or ""
  for dir in string.gmatch(envPath .. ":", "([^:]*):") do
    if #dir > 0 then
      local candidate = dir .. "/" .. binary
      if noctalia.fileExists(candidate) then
        return candidate
      end
    end
  end
  return binary
end

function M.binary()
  return M.expandBinary(M.cfg("binary", "xm5ctl"))
end

function M.channel()
  return tostring(M.cfg("channel", "9"))
end

function M.address()
  return tostring(M.cfg("address", ""))
end

-- global args that must precede the subcommand
function M.globalArgs()
  local args = { M.binary() }
  local address = M.address()
  if address ~= "" then
    table.insert(args, "--address")
    table.insert(args, address)
  end
  table.insert(args, "--channel")
  table.insert(args, M.channel())
  table.insert(args, "--state-file")
  table.insert(args, M.stateFile())
  table.insert(args, "--socket-file")
  table.insert(args, M.socketFile())
  return args
end

-- Build the argv for an action published by the widget/panel.
function M.actionArgv(req)
  local args = M.globalArgs()
  local action = req.action
  if action == "refresh" then
    table.insert(args, "status")
    table.insert(args, "--json")
  elseif action == "noise" then
    table.insert(args, "noise")
    table.insert(args, req.mode)
  elseif action == "ambient-level" then
    table.insert(args, "ambient-level")
    table.insert(args, tostring(req.level))
  elseif action == "focus-on-voice" then
    table.insert(args, "focus-on-voice")
    table.insert(args, req.value and "on" or "off")
  elseif action == "speak-to-chat" then
    table.insert(args, "speak-to-chat")
    table.insert(args, req.value and "on" or "off")
  elseif action == "dsee" then
    table.insert(args, "dsee")
    table.insert(args, req.value and "on" or "off")
  elseif action == "connection" then
    table.insert(args, "connection")
    table.insert(args, req.mode == "connection_quality" and "quality" or "stable")
  elseif action == "volume" then
    table.insert(args, "volume")
    table.insert(args, tostring(req.level))
  elseif action == "power-off" then
    table.insert(args, "power-off")
  else
    return nil
  end
  return args
end

-- The single systemd-run statement that launches/keeps the detector daemon.
function M.daemonCommand()
  local idle = M.cfg("keep_alive", true) and 0 or tonumber(M.cfg("idle_timeout", 90)) or 90
  local poll = tonumber(M.cfg("refresh_seconds", 15)) or 15
  local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
  end
  local parts = {
    "systemctl --user reset-failed xm5d 2>/dev/null; systemctl --user stop xm5d 2>/dev/null; systemd-run --user",
    "--unit=xm5d --collect",
    "--property=Restart=on-failure --property=RestartSec=3",
    "--",
    shq(M.binary()),
  }
  -- global options must precede the `daemon` subcommand
  local address = M.address()
  if address ~= "" then
    table.insert(parts, "--address")
    table.insert(parts, shq(address))
  end
  table.insert(parts, "--channel")
  table.insert(parts, shq(M.channel()))
  table.insert(parts, "--state-file")
  table.insert(parts, shq(M.stateFile()))
  table.insert(parts, "--socket-file")
  table.insert(parts, shq(M.socketFile()))
  table.insert(parts, "daemon")
  table.insert(parts, "--poll")
  table.insert(parts, shq(tostring(poll)))
  table.insert(parts, "--idle-timeout")
  table.insert(parts, shq(tostring(idle)))
  return table.concat(parts, " ")
end

-- Presentation -----------------------------------------------------------

M.COLOR_ANC = "#89b4fa"
M.COLOR_AMBIENT = "#f9e2af"
M.COLOR_OFF = "#9399b2"
M.COLOR_LOW = "#f38ba8"
M.COLOR_OK = "#a6e3a1"

function M.deviceShort(model)
  if type(model) ~= "string" or model == "" then
    return "XM5"
  end
  local short = model:gsub("^WH%-1000", ""):gsub("^WF%-1000", "")
  if short == "" then
    return model
  end
  return short
end

function M.noiseGlyph(noise)
  if noise == "anc" then
    return "headphones"
  elseif noise == "ambient" then
    return "ear"
  end
  return "headphones-off"
end

function M.noiseColor(noise)
  if noise == "anc" then
    return M.COLOR_ANC
  elseif noise == "ambient" then
    return M.COLOR_AMBIENT
  end
  return M.COLOR_OFF
end

function M.noiseShort(noise)
  if noise == "anc" then
    return "NC"
  elseif noise == "ambient" then
    return "AMB"
  end
  return "OFF"
end

function M.batteryColor(level)
  if type(level) ~= "number" then
    return M.COLOR_OFF
  end
  if level <= 15 then
    return M.COLOR_LOW
  end
  return M.COLOR_OK
end

return M
