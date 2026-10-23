--!nonstrict
-- Launcher provider for gery/notes-md (prefix /n).
--
-- Filename/path search runs in memory against the index published by the
-- service. Content search is an async ripgrep over the notes root; late
-- results are dropped unless the query still matches.

local notes = require("./lib/notes.luau")

local lastText = ""
local contentSeq = 0
local lastScanRequest = 0
local MAX_ROWS = 8

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function displayRel(rel)
  if rel == nil or rel == "" then return tr("ui.loose") end
  return (rel:gsub("/", " / "))
end

local function snapshot()
  local value = noctalia.state.get(notes.INDEX_KEY)
  if type(value) ~= "table" then return nil end
  if type(value.entries) ~= "table" then return nil end
  return value
end

local function noteScore(query, e)
  local stem = notes.stem(e.name)
  local pathScore = noctalia.fuzzyScore(query, e.rel)
  local titleScore = noctalia.fuzzyScore(query, stem)
  if pathScore == nil and titleScore == nil then return nil end
  local score = math.max(titleScore or 0, (pathScore or 0) * 0.55)
  if stem:lower():find(query:lower(), 1, true) then score += 1000 end
  return score
end

local function baseResults(text, snap)
  local results = {}
  local query = notes.trim(text)
  if query == "" then
    results[#results + 1] = {
      id = "action:open",
      title = tr("launcher.open_panel"),
      subtitle = tr("launcher.open_panel_sub"),
      glyph = "notes",
      score = 1000,
    }
    results[#results + 1] = {
      id = "action:new",
      title = tr("launcher.new_note"),
      subtitle = tr("launcher.new_note_sub"),
      glyph = "file-plus",
      score = 900,
    }
    if snap ~= nil then
      local recent = {}
      for _, e in ipairs(snap.entries) do
        if not e.dir then recent[#recent + 1] = e end
      end
      table.sort(recent, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
      for index, e in ipairs(recent) do
        if index > MAX_ROWS then break end
        results[#results + 1] = {
          id = "note:" .. e.rel,
          title = notes.stem(e.name),
          subtitle = displayRel(e.parent),
          glyph = "markdown",
          score = 800 - index,
        }
      end
    end
    return results
  end

  if snap == nil then
    results[#results + 1] = {
      id = "action:open",
      title = tr("launcher.indexing"),
      subtitle = tr("launcher.indexing_sub"),
      glyph = "refresh",
      score = 1000,
    }
    return results
  end

  local matched = {}
  for _, e in ipairs(snap.entries) do
    if not e.dir then
      local score = noteScore(query, e)
      if score ~= nil then
        matched[#matched + 1] = { entry = e, score = score }
      end
    end
  end
  table.sort(matched, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.entry.rel < b.entry.rel
  end)
  for index, item in ipairs(matched) do
    if index > MAX_ROWS then break end
    local e = item.entry
    results[#results + 1] = {
      id = "note:" .. e.rel,
      title = notes.stem(e.name),
      subtitle = displayRel(e.parent),
      glyph = "markdown",
      score = 500 - index,
    }
  end
  return results
end

local function contentSearch(text, snap, base)
  if snap == nil then return end
  local query = notes.trim(text)
  if #query < 2 then return end
  if noctalia.getConfig("content_search") == false then return end

  local rg = notes.expandBinary("rg")
  local argv = {
    rg,
    "--files-with-matches",
    "--no-messages",
    "--fixed-strings",
    "--max-count", "1",
    "--max-filesize", "2M",
    "-g", "*" .. notes.suffix(),
    "--",
    query,
    snap.root,
  }

  contentSeq += 1
  local seq = contentSeq
  local started = noctalia.runAsync(argv, function(result)
    if seq ~= contentSeq or lastText ~= text then return end
    if result == nil or result.timedOut or result.exitCode ~= 0 then return end
    local seen = {}
    for _, row in ipairs(base) do seen[row.id] = true end
    local added = 0
    for line in (tostring(result.stdout or "") .. "\n"):gmatch("(.-)\n") do
      if added >= MAX_ROWS then break end
      local rel = notes.relative(snap.root, line)
      if rel ~= nil and rel ~= "" and not seen["note:" .. rel] then
        local title = notes.stem(notes.base(rel))
        base[#base + 1] = {
          id = "note:" .. rel,
          title = title,
          subtitle = tr("launcher.content_match", { path = displayRel(notes.parent(rel)) }),
          glyph = "markdown",
          score = 200 - added,
        }
        seen["note:" .. rel] = true
        added += 1
      end
    end
    if added > 0 then launcher.setResults(text, base) end
  end)
  if not started then return end
end

-- The host closes the active panel right after onActivate returns, which would
-- immediately undo a panel opened from inside onActivate. Rewriting the launcher
-- input instead makes the host skip that close; the re-run onQuery then opens
-- the panel from a clean call stack (same pattern as gery/note-tuxedo).
local pendingOpen = false

local function requestOpen()
  pendingOpen = true
  launcher.setQuery(" ")
end

function onQuery(text)
  text = text or ""
  lastText = text
  contentSeq += 1

  if pendingOpen then
    pendingOpen = false
    noctalia.togglePanel(notes.PANEL_ID)
    launcher.setResults(text, {})
    return
  end

  local snap = snapshot()
  if snap == nil then
    local now = noctalia.nowMs()
    if now - lastScanRequest > 4000 then
      lastScanRequest = now
      notes.requestScan()
    end
  end

  local results = baseResults(text, snap)
  launcher.setResults(text, results)
  contentSearch(text, snap, results)
end

function onActivate(id)
  local panelOpen = noctalia.state.get(notes.PANEL_OPEN_KEY) == true
  if id == "action:open" then
    if not panelOpen then requestOpen() end
  elseif id == "action:new" then
    noctalia.state.set(notes.NEW_KEY, true)
    if not panelOpen then requestOpen() end
  elseif type(id) == "string" then
    local rel = id:match("^note:(.+)$")
    if rel ~= nil then
      noctalia.state.set(notes.OPEN_KEY, rel)
      if not panelOpen then requestOpen() end
    end
  end
end
