--!nonstrict
-- Sole owner of the `tuxedo` CLI. Polls `tuxedo ls --json` on an interval and
-- executes mutations on request; the widget, panel and launcher only read
-- noctalia.state and never spawn a process of their own. Needs plugin_api 22
-- (require) and 24 (argv tables).

local note = require("./lib/note.luau")

local function intervalMs()
  local secs = tonumber(note.cfg("refresh_seconds", "30")) or 30
  if secs < 5 then secs = 5 end
  return math.floor(secs * 1000)
end

local function failure(code, detail)
  return { code = code, detail = note.trim(detail) }
end

local function classify(result)
  if result == nil then return failure("spawn_failed") end
  if result.timedOut then return failure("timed_out") end
  local stderr = tostring(result.stderr or "")
  if result.exitCode == 127 then return failure("not_installed", stderr) end
  if result.exitCode ~= 0 then
    return failure(
      "failed",
      stderr:find("%S") and stderr or ("tuxedo exited with code " .. tostring(result.exitCode))
    )
  end
  return failure("no_data", stderr)
end

-- ── Polling ───────────────────────────────────────────────────────────────────

local inFlight = false
local pending = false
local lastStart = 0
-- A floor between spawns: opening the panel asks for a read, and a panel opens
-- as fast as a pointer can click.
local MIN_GAP_MS = 1500

local refresh -- forward declaration

local function parseTasks(result)
  local decoded = noctalia.json.decode(result.stdout or "")
  if type(decoded) ~= "table" then return nil end
  local out = {}
  for _, t in ipairs(decoded) do
    if type(t) == "table" and type(t.raw) == "string" then
      out[#out + 1] = {
        n = tonumber(t.n) or 0,
        raw = tostring(t.raw),
        done = t.done == true,
        priority = type(t.priority) == "string" and t.priority or nil,
        due = type(t.due) == "string" and t.due or nil,
        created = type(t.created) == "string" and t.created or nil,
        projects = type(t.projects) == "table" and t.projects or {},
        contexts = type(t.contexts) == "table" and t.contexts or {},
      }
    end
  end
  return out
end

refresh = function()
  if inFlight then
    pending = true
    return
  end
  local now = noctalia.nowMs()
  if MIN_GAP_MS - (now - lastStart) > 0 then
    -- Too soon after the last read: let the tick retry shortly instead of
    -- hammering the CLI.
    pending = true
    noctalia.setUpdateInterval(300)
    return
  end
  lastStart = now
  pending = false
  noctalia.setUpdateInterval(intervalMs())
  inFlight = true
  noctalia.state.set("polling", true)

  local started = noctalia.runAsync(note.argv({ "ls", "--json" }), function(result)
    inFlight = false
    noctalia.state.set("polling", false)
    if result ~= nil and not result.timedOut and result.exitCode == 0 then
      local tasks = parseTasks(result)
      if tasks ~= nil then
        noctalia.state.set("tasks", tasks)
        noctalia.state.set("counts", note.summarize(tasks))
        noctalia.state.set("error", failure(""))
      else
        noctalia.state.set("error", classify(result))
      end
    else
      noctalia.state.set("error", classify(result))
    end
    if pending then refresh() end
  end, 20000)

  -- A refusal to spawn never calls back, and the poller would sit in flight
  -- forever.
  if not started then
    inFlight = false
    pending = false
    noctalia.state.set("polling", false)
    noctalia.state.set("error", failure("spawn_failed"))
  end
end

-- ── Mutations ─────────────────────────────────────────────────────────────────

local busy = false

local function findTask(n)
  local tasks = noctalia.state.get("tasks")
  if type(tasks) ~= "table" then return nil end
  for _, t in ipairs(tasks) do
    if t.n == n then return t end
  end
  return nil
end

-- Strip the completion markers from a raw todo.txt line so a completed task can
-- be reopened with `replace` (the CLI's `do` only ever completes).
local function undoneText(raw)
  local rest = tostring(raw or ""):gsub("^x%s+", "")
  rest = rest:gsub("^%d%d%d%d%-%d%d%-%d%d%s+", "")
  return rest
end

local function runMutation(args)
  if busy then return end
  busy = true
  noctalia.state.set("busy", true)

  local started = noctalia.runAsync(note.argv(args), function(result)
    busy = false
    noctalia.state.set("busy", false)
    if result == nil or result.timedOut or result.exitCode ~= 0 then
      local f = classify(result)
      noctalia.notify(noctalia.tr("ui.mutation_failed"), f.detail ~= "" and f.detail or noctalia.tr("ui.mutation_failed_hint"))
    end
    refresh()
  end, 15000)

  if not started then
    busy = false
    noctalia.state.set("busy", false)
    noctalia.notify(noctalia.tr("ui.mutation_failed"), noctalia.tr("ui.spawn_failed"))
    refresh()
  end
end

-- ── Requests from the panel / launcher ────────────────────────────────────────

local lastReqSeq = 0

noctalia.state.watch("request", function(req)
  if type(req) ~= "table" then return end
  -- Monotonic wall clock: entries set `seq = noctalia.nowMs()`, so a stale or
  -- re-delivered request (equal or older) is ignored while cross-VM ordering is
  -- preserved without a shared counter.
  if type(req.seq) ~= "number" or req.seq <= lastReqSeq then return end
  lastReqSeq = req.seq
  local action = req.action
  if action == "refresh" then
    refresh()
  elseif action == "add" and type(req.text) == "string" and note.trim(req.text) ~= "" then
    runMutation({ "add", note.trim(req.text) })
  elseif action == "toggle" and tonumber(req.n) then
    local t = findTask(tonumber(req.n))
    if t ~= nil then
      if t.done then
        runMutation({ "replace", tostring(t.n), undoneText(t.raw) })
      else
        runMutation({ "do", tostring(t.n) })
      end
    end
  elseif action == "pri" and tonumber(req.n) and type(req.priority) == "string" then
    runMutation({ "pri", tostring(tonumber(req.n)), req.priority })
  elseif action == "depri" and tonumber(req.n) then
    runMutation({ "depri", tostring(tonumber(req.n)) })
  elseif action == "replace" and tonumber(req.n) and type(req.text) == "string" and note.trim(req.text) ~= "" then
    runMutation({ "replace", tostring(tonumber(req.n)), note.trim(req.text) })
  elseif action == "delete" and tonumber(req.n) then
    runMutation({ "-f", "del", tostring(tonumber(req.n)) })
  end
end)

function onIpc(event, payload)
  if event == "refresh" then
    refresh()
  elseif event == "add" and type(payload) == "string" and note.trim(payload) ~= "" then
    runMutation({ "add", note.trim(payload) })
  end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function update()
  -- Watchdog: a stalled child must never wedge polling permanently.
  if inFlight and noctalia.nowMs() - lastStart > 15000 then
    inFlight = false
  end
  if inFlight then return end
  refresh()
end

function onConfigChanged()
  noctalia.setUpdateInterval(intervalMs())
  refresh()
end

noctalia.setUpdateInterval(intervalMs())
refresh()
