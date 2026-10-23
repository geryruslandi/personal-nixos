--!nonstrict
-- Index service for gery/notes-md.
--
-- Walks the notes root off the UI thread with a single `find` invocation and
-- publishes a flat entry list over noctalia.state. The panel builds its tree
-- and search from that list, and the launcher searches it in memory. Writes
-- done by the panel bump the index; a stale timer covers external changes.
-- Needs plugin_api 22 (require) and 24 (argv tables).

local notes = require("./lib/notes.luau")

local MAX_DEPTH = 12
local MAX_ENTRIES = 20000
local STALE_MS = 5 * 60 * 1000
local WATCHDOG_MS = 45 * 1000

local lastRoot = nil
local lastScan = 0
local lastStart = 0
local inFlight = false
local pending = false
local scanToken = 0

local function rootMissing(root)
  return not noctalia.fileExists(root)
end

local function entryFor(root, rel, isDir, mtime)
  return {
    rel = rel,
    name = notes.base(rel),
    dir = isDir,
    parent = notes.parent(rel),
    space = notes.entrySpace(rel, isDir),
    mtime = tonumber(mtime) or 0,
  }
end

local function parseFind(root, stdout, wasTruncated)
  local entries = {}
  local truncated = wasTruncated == true
  for line in (tostring(stdout or "") .. "\n"):gmatch("(.-)\n") do
    if #entries >= MAX_ENTRIES then
      truncated = true
      break
    end
    local kind, mtime, path = line:match("^(%a)\t([%d%.]+)\t(.*)$")
    if kind ~= nil then
      local rel = notes.relative(root, path)
      if rel ~= nil and rel ~= "" then
        entries[#entries + 1] = entryFor(root, rel, kind == "D", mtime)
      end
    end
  end
  return entries, truncated
end

local function findArgv(root)
  local ignored = notes.ignored()
  local argv = {
    notes.expandBinary("find"), root,
    "-mindepth", "1", "-maxdepth", tostring(MAX_DEPTH),
    "-name", ".*", "-prune", "-o",
  }
  for _, name in ipairs(ignored) do
    argv[#argv + 1] = "-name"
    argv[#argv + 1] = name
    argv[#argv + 1] = "-prune"
    argv[#argv + 1] = "-o"
  end
  local suffix = notes.suffix()
  argv[#argv + 1] = "-type"
  argv[#argv + 1] = "d"
  argv[#argv + 1] = "-printf"
  argv[#argv + 1] = "D\t%T@\t%p\n"
  argv[#argv + 1] = "-o"
  argv[#argv + 1] = "-type"
  argv[#argv + 1] = "f"
  argv[#argv + 1] = "-iname"
  argv[#argv + 1] = "*" .. suffix
  argv[#argv + 1] = "-printf"
  argv[#argv + 1] = "F\t%T@\t%p\n"
  return argv
end

-- Pure-Luau fallback used when `find` is unavailable. Depth- and entry-capped
-- so a huge Documents tree cannot wedge a service tick.
local function walk(root)
  local out = {}
  local truncated = false
  local queue = { { rel = "", depth = 0 } }
  local head = 1
  while head <= #queue do
    if #out >= MAX_ENTRIES then
      truncated = true
      break
    end
    local item = queue[head]
    head += 1
    local list = noctalia.listDir(notes.path(root, item.rel))
    if list ~= nil then
      table.sort(list)
      for _, name in ipairs(list) do
        if name:sub(1, 1) ~= "." and not notes.isIgnored(name) then
          if #out >= MAX_ENTRIES then
            truncated = true
            break
          end
          local rel = (item.rel == "") and name or (item.rel .. "/" .. name)
          local info = noctalia.fileInfo(notes.path(root, rel))
          if info ~= nil then
            if info.isDir then
              out[#out + 1] = entryFor(root, rel, true, info.mtime)
              if item.depth + 1 < MAX_DEPTH then
                queue[#queue + 1] = { rel = rel, depth = item.depth + 1 }
              else
                truncated = true
              end
            elseif notes.isNote(name) then
              out[#out + 1] = entryFor(root, rel, false, info.mtime)
            end
          end
        end
      end
    end
  end
  return out, truncated
end

local function publish(root, entries, truncated, err, startedAt, triggerSeq)
  table.sort(entries, function(a, b) return a.rel < b.rel end)
  noctalia.state.set(notes.INDEX_KEY, {
    root = root,
    entries = entries,
    scannedAt = noctalia.nowMs(),
    -- Scan start (not publish time): the panel uses this to discard a scan
    -- that began before its latest file mutation.
    startedAt = startedAt,
    triggerSeq = triggerSeq,
    truncated = truncated == true,
    error = err,
    count = notes.countNotes(entries),
  })
end

local function finish(root, entries, truncated, err, startedAt, triggerSeq)
  lastRoot = root
  lastScan = noctalia.nowMs()
  publish(root, entries or {}, truncated, err, startedAt, triggerSeq)
end

local function scan()
  if inFlight then
    pending = true
    return
  end
  local root = notes.root()
  local triggerSeq = noctalia.state.get(notes.BUMP_KEY) or 0
  if rootMissing(root) then
    finish(root, {}, false, "root_missing", noctalia.nowMs(), triggerSeq)
    return
  end
  inFlight = true
  lastStart = noctalia.nowMs()
  local startedAt = lastStart
  pending = false
  scanToken += 1
  local token = scanToken

  local started = noctalia.runAsync(findArgv(root), function(result)
    if token ~= scanToken then
      inFlight = false
      return
    end
    inFlight = false
    if result ~= nil and not result.timedOut and result.exitCode == 0 then
      local entries, truncated = parseFind(root, result.stdout, result.stdoutTruncated)
      finish(root, entries, truncated, nil, startedAt, triggerSeq)
    else
      local entries, truncated = walk(root)
      local err = nil
      if result ~= nil and result.timedOut then
        err = "timed_out"
      elseif result == nil or result.exitCode == 127 then
        err = "find_missing"
      end
      finish(root, entries, truncated, err, startedAt, triggerSeq)
    end
  end, 30000)

  if not started then
    inFlight = false
    local entries, truncated = walk(root)
    finish(root, entries, truncated, "spawn_failed", startedAt, triggerSeq)
  end
end

local function request()
  pending = true
end

noctalia.state.watch(notes.BUMP_KEY, request)
noctalia.state.watch(notes.SCAN_KEY, request)

function update()
  local now = noctalia.nowMs()
  if inFlight and now - lastStart > WATCHDOG_MS then
    inFlight = false
  end
  if inFlight then return end
  if pending or lastRoot ~= notes.root() or (now - lastScan) > STALE_MS then
    scan()
  end
end

function onConfigChanged()
  lastRoot = nil
  pending = true
end

noctalia.setUpdateInterval(1000)
scan()
