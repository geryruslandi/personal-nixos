--!nonstrict
-- Launcher provider behind `/todo`. Empty query offers the kanban board (and
-- its group variants); free text offers a quick `add`; matching pending tasks
-- offer to complete/uncomplete. Reads noctalia.state only.

local note = require("./lib/note.luau")

local lastQuery = ""
-- A board activation first rewrites the launcher input (setQuery) instead of
-- toggling immediately: the host then skips its post-activation close, and the
-- re-run onQuery opens the panel from a clean call stack. Opening directly
-- from onActivate gets instantly undone by finishActivation() closing the
-- active panel (which is already the freshly opened board).
local pendingBoard = nil

local function send(tbl)
  tbl.seq = noctalia.nowMs()
  noctalia.state.set("request", tbl)
end

local function subtitle(t)
  local parts = {}
  if t.priority ~= nil and t.priority ~= "" then
    parts[#parts + 1] = noctalia.tr("ui.priority", { p = t.priority })
  end
  if t.due ~= nil and t.due ~= "" then parts[#parts + 1] = t.due end
  for _, p in ipairs(t.projects) do parts[#parts + 1] = "+" .. p end
  for _, c in ipairs(t.contexts) do parts[#parts + 1] = "@" .. c end
  return table.concat(parts, " · ")
end

local function openBoard(group)
  noctalia.state.set("openBoard", { seq = noctalia.nowMs(), group = group })
  -- Only open when closed; an already-open board keeps its grouping (the state
  -- ping above re-renders it). Avoids the launcher's toggle hitting a live board.
  if noctalia.state.get("boardOpen") ~= true then
    noctalia.togglePanel("gery/note-tuxedo:todo-kanban")
  end
end

function onQuery(text)
  lastQuery = text or ""

  -- Deferred board open queued by onActivate (see pendingBoard).
  if pendingBoard ~= nil then
    local group = pendingBoard
    pendingBoard = nil
    openBoard(group)
    launcher.setResults(lastQuery, {})
    return
  end

  local q = note.trim(lastQuery)
  local results = {}

  if q == "" then
    results[#results + 1] = {
      id = "board:flow",
      title = noctalia.tr("ui.kanban.open_board"),
      subtitle = noctalia.tr("ui.kanban.open_board_sub"),
      glyph = "layout-kanban",
      score = 1000,
    }
    results[#results + 1] = {
      id = "board:project",
      title = noctalia.tr("ui.kanban.open_project"),
      glyph = "folder",
      score = 950,
    }
    results[#results + 1] = {
      id = "board:priority",
      title = noctalia.tr("ui.kanban.open_priority"),
      glyph = "flag",
      score = 900,
    }
    results[#results + 1] = {
      id = "board:context",
      title = noctalia.tr("ui.kanban.open_context"),
      glyph = "map-pin",
      score = 800,
    }
  elseif q ~= "" then
    results[#results + 1] = {
      id = "add",
      title = noctalia.tr("ui.launcher.add", { text = q }),
      subtitle = noctalia.tr("ui.launcher.add_sub"),
      glyph = "plus",
      score = 1000,
    }

    local all = noctalia.state.get("tasks")
    if type(all) == "table" then
      local needle = q:lower()
      local matched = 0
      for _, t in ipairs(all) do
        if not t.done and t.raw:lower():find(needle, 1, true) then
          matched = matched + 1
          results[#results + 1] = {
            id = "task:" .. tostring(t.n),
            title = t.raw,
            subtitle = subtitle(t),
            glyph = "list-check",
            score = 500 - matched,
          }
          if matched >= 8 then break end
        end
      end
    end
  end

  launcher.setResults(lastQuery, results)
end

function onActivate(id)
  if id == "add" then
    local q = note.trim(lastQuery)
    if q ~= "" then send({ action = "add", text = q }) end
  elseif type(id) == "string" and id:sub(1, 6) == "board:" then
    -- Queue the open and rewrite the input: a setQuery in onActivate makes the
    -- host skip its post-activation close, and the re-run onQuery performs the
    -- actual toggle from outside the activation call stack.
    pendingBoard = id:sub(7)
    launcher.setQuery(" ")
  elseif type(id) == "string" then
    local n = tonumber(id:match("^task:(%d+)$"))
    if n ~= nil then send({ action = "toggle", n = n }) end
  end
end
