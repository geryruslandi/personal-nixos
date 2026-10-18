--!nonstrict
-- Request/response channel between browser VMs (launcher, panels) and the
-- service: requests go out on `noctalia.state "cmd"`, responses come back on
-- `rsp` matched by a per-VM sequence id. Gives callers proper correlation so
-- concurrent requests can't mix up responses.
--
-- Note: entry lifecycle hooks (onQuery/onOpen/onFrameTick/...) must be defined
-- as globals in the *entry* script — modules live in their own global env, so
-- panels wire `onFrameTick` to `rpc.expire()` themselves via a helper in their
-- own file.

local M = {}

local counter = 0
local pending = {}
local VMID = tostring(math.floor(noctalia.nowMs())) .. "-" .. tostring(math.random(1000, 9999))
local RESPONSE_TIMEOUT_MS = 45000

function M.init()
  noctalia.state.watch("rsp", function(rsp)
    if type(rsp) ~= "table" or type(rsp.seq) ~= "string" then
      return
    end
    local entry = pending[rsp.seq]
    if entry == nil then
      return
    end
    pending[rsp.seq] = nil
    entry.cb(rsp.ok == true, rsp.data, rsp.error)
  end)
end

-- cb(ok, data, error). Returns the seq for reference.
function M.send(action, payload, cb)
  counter += 1
  local seq = VMID .. "-" .. tostring(counter)
  local cmd = { seq = seq, action = action }
  if type(payload) == "table" then
    for k, v in pairs(payload) do
      if k ~= "seq" and k ~= "action" then
        cmd[k] = v
      end
    end
  end
  if cb ~= nil then
    pending[seq] = { cb = cb, startedMs = noctalia.nowMs() }
  end
  noctalia.state.set("cmd", cmd)
  return seq
end

function M.notify(action, payload)
  M.send(action, payload, nil)
end

function M.pendingCount()
  local n = 0
  for _ in pairs(pending) do
    n += 1
  end
  return n
end

-- Drops stale requests (service dead / crashed mid-op) so callers cannot get
-- stuck in a busy state. Returns the number of expired entries.
function M.expire()
  local now = noctalia.nowMs()
  local expired = 0
  for seq, entry in pairs(pending) do
    if now - entry.startedMs > RESPONSE_TIMEOUT_MS then
      pending[seq] = nil
      expired += 1
      entry.cb(false, nil, noctalia.tr("error.timeout"))
    end
  end
  return expired
end

return M
