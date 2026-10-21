--!nonstrict
-- Kanban panel: opened from the `/todo` launcher. The default "flow" board is a
-- classic Todo / Doing / Done: a task is Doing while it carries the stage
-- context `@doing` (todo.txt has no native in-progress state, so the board
-- manages that one token and leaves every other token alone). The group modes
-- (project / context / priority / none) remain available from the switcher.
-- Cards are ui.dragSource items and every column body is a ui.dropZone. A drop
-- rewrites the task in plain todo.txt terms via a single `replace`, completes
-- via `do`, and reopens a done card by dropping it on Todo or Doing. No drag
-- needed either: the checkbox, priority cycle, inline edit and per-column "+"
-- add work alone. Reads noctalia.state only; the service stays the sole owner
-- of the CLI. Needs plugin_api 22 (require) and 24 (argv tables).

local note = require("./lib/note.luau")

local MAX_DONE_CARDS = 25
-- Prop-safe encoding of lib/note's "\0none" bucket (\0 must not travel inside
-- drop-zone values or keys).
local NONE = "none"
-- Context token marking a task as "in progress" on the flow board.
local STAGE_CTX = "doing"

local tasks = {}
local counts = nil
local failure = note.NO_FAILURE
local polling = false
local busy = false

local groupMode = note.cfg("default_group_by", "flow")
if groupMode ~= "flow" and groupMode ~= "project" and groupMode ~= "priority" and groupMode ~= "context" and groupMode ~= "none" then
  groupMode = "flow"
end
local search = ""
local addCol = nil
local addColText = ""
-- ui.input is uncontrolled: the host keeps the text across renders unless the
-- key changes. Every submitted add bumps this nonce so the field re-seeds empty.
local addNonce = 0
local editingN = nil
local editText = ""
-- Latest consumed openBoard sequence, so stale launcher pings don't switch
-- groupMode after the user has picked one manually.
local lastOpenSeq = 0

local render -- forward declaration

-- ── Requests to the service ───────────────────────────────────────────────────

local reqSeq = 0
local function request(tbl)
  -- Monotonic wall clock, so the service can order requests across VMs (the
  -- launcher and list panel send through the same channel).
  local seq = noctalia.nowMs()
  if seq <= reqSeq then seq = reqSeq + 0.001 end
  reqSeq = seq
  tbl.seq = seq
  noctalia.state.set("request", tbl)
end

local function findTask(n)
  for _, t in ipairs(tasks) do
    if t.n == n then return t end
  end
  return nil
end

-- ── Text surgery (one `replace` per drop; the file stays plain todo.txt) ──────

-- Strip the completion markers ("x " and the completion date) of a DONE line
-- — mirrors the service's undoneText, better kept local because requiring
-- service.luau would start its poller inside this VM. Pending lines keep their
-- leading creation date untouched.
local function reopenedRaw(raw)
  local rest = tostring(raw or ""):gsub("^x%s+", "")
  rest = rest:gsub("^%d%d%d%d%-%d%d%-%d%d%s+", "")
  return rest
end

-- Drop every token of one sigil ("+" or "@") from the text; the new tag, when
-- set, takes the first dropped token's slot in place (keeps the line's visual
-- order); no such token anywhere means append. The other sigil's tokens stay.
local function withTag(raw, isProject, tag)
  local sigil = isProject and "+" or "@"
  local replaced = false
  local out = {}
  for tok in tostring(raw):gmatch("%S+") do
    if tok:sub(1, 1) == sigil then
      if not replaced and tag ~= nil and tag ~= "" then
        out[#out + 1] = sigil .. tag
        replaced = true
      end
    else
      out[#out + 1] = tok
    end
  end
  if not replaced and tag ~= nil and tag ~= "" then out[#out + 1] = sigil .. tag end
  return table.concat(out, " ")
end

-- Text a task needs for its card to live in column (mode, key). Rebuilding a
-- line is purely textual: [createdDate] [(priority)] <tokens>; a done card re-
-- opened by dropping it into any group column loses its "x <date>" record.
local function rebasedText(t, mode, key)
  local head = t.done and reopenedRaw(t.raw) or tostring(t.raw)

  -- Leading created date (optional in todo.txt).
  local dateTok = head:match("^(%d%d%d%d%-%d%d%-%d%d)%s")
  if dateTok ~= nil then
    head = (head:sub(#dateTok + 1):gsub("^%s+", ""))
  end
  -- The old priority token must not stay inside the body; it is re-emitted from
  -- t.priority (the parse-provided value) below.
  local body = (head:gsub("^%(%a%)%s*", ""))
  body = note.trim(body)

  local pri = t.priority
  if mode == "project" then
    body = withTag(body, true, (key ~= NONE and key ~= "") and key or nil)
  elseif mode == "context" then
    body = withTag(body, false, (key ~= NONE and key ~= "") and key or nil)
  elseif mode == "priority" then
    -- A priority column replaces the old priority outright (none = depri).
    pri = (key ~= NONE and key ~= "") and key or nil
  end

  local prefix = ""
  if dateTok ~= nil then prefix = dateTok .. " " end
  if pri ~= nil and pri ~= "" then prefix = prefix .. "(" .. pri .. ") " end
  return prefix .. body
end

-- Which column a card currently renders in (mirrors lib/note's first-of rule).
local function cardColKey(t, mode)
  if mode == "priority" then
    local p = t.priority
    if p == nil or p == "" then return NONE end
    return tostring(p)
  end
  local field = mode == "context" and "contexts" or "projects"
  local list = type(t[field]) == "table" and t[field] or {}
  if #list == 0 then return NONE end
  return tostring(list[1])
end

-- "Doing" stage: the single @doing context the flow board owns.
local function hasDoing(t)
  for _, c in ipairs(t.contexts or {}) do
    if tostring(c):lower() == STAGE_CTX then return true end
  end
  return false
end

-- Move a task between Todo (<-> wantDoing) and Doing columns. Only the @doing
-- token is added/removed; every other token (other @contexts, +projects,
-- due:/note: etc.), the created date and the priority are preserved verbatim.
-- Done cards are reopened first, so dropping onto either column reopens there.
local function stageText(t, wantDoing)
  local head = t.done and reopenedRaw(t.raw) or tostring(t.raw)

  local dateTok = head:match("^(%d%d%d%d%-%d%d%-%d%d)%s")
  if dateTok ~= nil then
    head = (head:sub(#dateTok + 1):gsub("^%s+", ""))
  end
  local body = (head:gsub("^%(%a%)%s*", ""))
  body = note.trim(body)

  local kept = {}
  for tok in body:gmatch("%S+") do
    local isStage = tok:sub(1, 1) == "@" and tok:sub(2):lower() == STAGE_CTX
    if not isStage then kept[#kept + 1] = tok end
  end
  if wantDoing then kept[#kept + 1] = "@" .. STAGE_CTX end

  local prefix = ""
  if dateTok ~= nil then prefix = dateTok .. " " end
  local pri = t.priority
  if pri ~= nil and pri ~= "" then prefix = prefix .. "(" .. pri .. ") " end
  return prefix .. table.concat(kept, " ")
end

-- Drop-zone ids disappear into UI props, so note.group's "\0none" key is swapped
-- for `NONE` everywhere (both sides of the comparison use this).
local function bucketColKey(g)
  if g.key == "\0none" then return NONE end
  return tostring(g.key)
end

-- ── Drops ─────────────────────────────────────────────────────────────────────

local function payloadTaskN(payload)
  if type(payload) == "string" then return tonumber(payload) end
  if type(payload) == "table" then return tonumber(payload.n) end
  return nil
end

local function handleDrop(payload, value)
  local mode, key = tostring(value or ""):match("^dz:([a-z]+):(.*)$")
  local t = findTask(payloadTaskN(payload))
  if mode == nil or t == nil then return end

  if mode == "done" then
    if not t.done then request({ action = "toggle", n = t.n }) end
    return
  end

  -- Flow board: Todo <-> Doing only adds/strips @doing. A done card is always
  -- processed (dropping it reopens in the target column); a pending card
  -- already in the target column is a no-op.
  if mode == "todo" or mode == "doing" then
    if groupMode ~= "flow" then return end
    local wantDoing = mode == "doing"
    if not t.done and hasDoing(t) == wantDoing then return end
    local text = stageText(t, wantDoing)
    if note.trim(text) == "" then return end
    request({ action = "replace", n = t.n, text = text })
    return
  end

  -- Tag modes: zones exist only for the active mode's columns (plus Done).
  if mode ~= groupMode then return end
  -- The none-mode board has one backlog column: dropping there re-tags
  -- nothing, so it is always a no-op.
  if mode == "none" then return end
  -- A pending card dropped back into its own column is a no-op; a done card is
  -- not — dropping it anywhere reopens it, even into "its" column.
  if not t.done and cardColKey(t, mode) == key then return end

  local text = rebasedText(t, mode, key)
  if note.trim(text) == "" then return end
  request({ action = "replace", n = t.n, text = text })
end

-- ── Visible model ─────────────────────────────────────────────────────────────

local function priorityRank(p)
  if p == nil or p == "" then return "ZZZ" end
  return p
end

local function compare(a, b)
  if a.priority ~= b.priority then return priorityRank(a.priority) < priorityRank(b.priority) end
  local ad = a.due ~= nil and a.due ~= "" and a.due or "9999-99-99"
  local bd = b.due ~= nil and b.due ~= "" and b.due or "9999-99-99"
  if ad ~= bd then return ad < bd end
  return a.n < b.n
end

local function matchesSearch(t)
  local needle = search:lower()
  if needle == "" then return true end
  return t.raw:lower():find(needle, 1, true) ~= nil
end

local function pendingTasks()
  local out = {}
  for _, t in ipairs(tasks) do
    if not t.done and matchesSearch(t) then out[#out + 1] = t end
  end
  table.sort(out, compare)
  return out
end

local function doneTasks()
  local out = {}
  for _, t in ipairs(tasks) do
    if t.done and matchesSearch(t) then out[#out + 1] = t end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return out
end

-- ── Card builders ─────────────────────────────────────────────────────────────

local function dueColor(t)
  if t.done then return note.COLOR.done end
  if note.isOverdue(t) then return note.COLOR.overdue end
  if note.isDueToday(t) then return note.COLOR.today end
  return note.COLOR.due
end

local function nextPriority(p)
  if p == nil or p == "" then return "A", "pri" end
  if p == "A" then return "B", "pri" end
  if p == "B" then return "C", "pri" end
  return nil, "depri"
end

local function submitEdit(n)
  local text = note.trim(editText)
  if text ~= "" then request({ action = "replace", n = n, text = text }) end
  editingN = nil
  editText = ""
  render()
end

local function editRow(t)
  return ui.row({
    key = "edit-" .. t.n,
    gap = 4,
    align = "center",
    paddingH = 4,
    paddingV = 4,
    radius = 8,
    fill = "surface_variant/0.5",
  }, {
    ui.input({
      key = "edit-input-" .. t.n,
      value = t.raw,
      flexGrow = 1,
      fontSize = 11,
      controlSize = "sm",
      focus = true,
      submitOnEnter = true,
      onChange = function(v) editText = v or "" end,
      onSubmit = function() submitEdit(t.n) end,
    }),
    ui.button({
      glyph = "device-floppy",
      variant = "primary",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.save"),
      onClick = function() submitEdit(t.n) end,
    }),
    ui.button({
      glyph = "x",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.cancel"),
      onClick = function() editingN = nil; editText = ""; render() end,
    }),
  })
end

local function card(t)
  if editingN == t.n then return editRow(t) end

  local top = {
    ui.toggle({
      checked = t.done,
      key = "tgl-" .. t.n,
      onChange = function() request({ action = "toggle", n = t.n }) end,
    }),
    ui.button({
      key = "pri-" .. t.n,
      text = (t.priority ~= nil and t.priority ~= "") and ("(" .. t.priority .. ")") or "·",
      variant = "ghost",
      controlSize = "sm",
      fontSize = 11,
      tooltip = noctalia.tr("ui.priority_cycle"),
      onClick = function()
        local next, action = nextPriority(t.priority)
        if action == "pri" then
          request({ action = "pri", n = t.n, priority = next })
        else
          request({ action = "depri", n = t.n })
        end
      end,
    }),
    ui.row({
      key = "txt-" .. t.n,
      flexGrow = 1,
      align = "start",
      onClick = function() editingN = t.n; editText = t.raw; render() end,
    }, {
      ui.label({
        text = t.raw,
        fontSize = 11,
        color = t.done and note.COLOR.done or "on_surface",
        flexGrow = 1,
        maxLines = 3,
      }),
    }),
    ui.button({
      key = "del-" .. t.n,
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.delete"),
      onClick = function() request({ action = "delete", n = t.n }) end,
    }),
  }

  local meta = {}
  if t.due ~= nil and t.due ~= "" then
    meta[#meta + 1] = ui.row({ key = "due-" .. t.n, gap = 2, align = "center" }, {
      ui.glyph({ name = "calendar-event", size = 10, color = dueColor(t) }),
      ui.label({ text = t.due, fontSize = 10, color = dueColor(t), maxLines = 1 }),
    })
  end
  local tags = {}
  for _, p in ipairs(t.projects) do tags[#tags + 1] = "+" .. p end
  for _, c in ipairs(t.contexts) do tags[#tags + 1] = "@" .. c end
  if #tags > 0 then
    meta[#meta + 1] = ui.label({
      key = "tags-" .. t.n,
      text = table.concat(tags, " "),
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 1,
      opacity = 0.8,
    })
  end

  local body = { ui.row({ key = "top-" .. t.n, gap = 4, align = "center" }, top) }
  if #meta > 0 then
    body[#body + 1] = ui.row({ key = "meta-" .. t.n, gap = 8, align = "center" }, meta)
  end

  return ui.dragSource({
    key = "src-" .. t.n,
    dragType = "kanban-task",
    -- String payload (host validation): the task's line number.
    payload = tostring(t.n),
    liftFromLayout = true,
    tooltip = noctalia.tr("ui.kanban.drag_hint"),
  }, {
    ui.column({
      key = "card-" .. t.n,
      gap = 3,
      padding = 5,
      radius = 8,
      fill = t.done and "surface_variant/0.18" or "surface/0.5",
    }, body),
  })
end

-- ── Column builders ───────────────────────────────────────────────────────────

local function submitColumnAdd(g, flowKey)
  local text = note.trim(addColText)
  if text ~= "" then
    if flowKey == "doing" then
      text = "@" .. STAGE_CTX .. " " .. text
    elseif flowKey == nil then
      -- Tag-mode column: seed the column's own tag.
      local key = bucketColKey(g)
      if key ~= NONE and key ~= "all" then
        if groupMode == "project" then
          text = "+" .. key .. " " .. text
        elseif groupMode == "context" then
          text = "@" .. key .. " " .. text
        elseif groupMode == "priority" then
          text = "(" .. key .. ") " .. text
        end
      end
    end
    request({ action = "add", text = text })
  end
  addColText = ""
  addCol = nil
  addNonce = addNonce + 1
  render()
end

local function columnAddRow(g, colId, flowKey)
  return ui.row({ key = "coladd-" .. colId, gap = 4, align = "center" }, {
    ui.input({
      key = "coladd-input-" .. colId .. "-" .. addNonce,
      placeholder = noctalia.tr("ui.add_placeholder"),
      flexGrow = 1,
      fontSize = 11,
      controlSize = "sm",
      focus = true,
      submitOnEnter = true,
      onChange = function(v) addColText = v or "" end,
      onSubmit = function() submitColumnAdd(g, flowKey) end,
    }),
    ui.button({
      text = noctalia.tr("ui.add"),
      glyph = "plus",
      variant = "primary",
      controlSize = "sm",
      onClick = function() submitColumnAdd(g, flowKey) end,
    }),
    ui.button({
      glyph = "x",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.cancel"),
      onClick = function() addCol = nil; addColText = ""; render() end,
    }),
  })
end

local function columnHeader(g, isDone, flowKey)
  local key = isDone and "done" or (flowKey or bucketColKey(g))
  local label
  local color
  if isDone then
    label = noctalia.tr("ui.kanban.done")
    color = "on_surface_variant"
  elseif flowKey == "todo" then
    label = noctalia.tr("ui.kanban.todo")
    color = "on_surface_variant"
  elseif flowKey == "doing" then
    label = noctalia.tr("ui.kanban.doing")
    color = "primary"
  else
    label = g.label ~= "" and g.label or noctalia.tr("ui.kanban.all")
    color = g.color or "on_surface_variant"
  end
  local nodes = {
    ui.label({
      text = label,
      fontSize = 11,
      fontWeight = "semibold",
      color = color,
      maxLines = 1,
    }),
    ui.label({ key = "cnt-" .. key, text = "(" .. tostring(#g.items) .. ")", fontSize = 10, color = "on_surface_variant" }),
    ui.spacer({ flexGrow = 1 }),
  }
  if not isDone then
    nodes[#nodes + 1] = ui.button({
      key = "coladd-btn-" .. key,
      glyph = "plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.kanban.add_to_column"),
      onClick = function()
        addCol = (addCol == key) and nil or key
        addColText = ""
        render()
      end,
    })
  end
  return ui.row({ key = "hd-" .. key, gap = 4, align = "center" }, nodes)
end

local function boardColumn(g, isDone, flowKey)
  local colId = isDone and "done" or (flowKey or bucketColKey(g))
  local cards = {}
  if #g.items == 0 then
    cards[1] = ui.row({ key = "hint-" .. colId, justify = "center", paddingV = 10 }, {
      ui.label({
        text = noctalia.tr("ui.kanban.empty_column"),
        fontSize = 10,
        color = "on_surface_variant",
        maxLines = 1,
      }),
    })
  else
    local only = isDone and MAX_DONE_CARDS or #g.items
    for i, t in ipairs(g.items) do
      if i > only then
        cards[#cards + 1] = ui.row({ key = "more-" .. colId, justify = "center", paddingV = 4 }, {
          ui.label({
            text = "+" .. tostring(#g.items - only) .. " " .. noctalia.tr("ui.kanban.more"),
            fontSize = 10,
            color = "on_surface_variant",
          }),
        })
        break
      end
      cards[#cards + 1] = card(t)
    end
  end

  -- Children arrays must have no nil holes (a nil entry truncates iteration),
  -- so the conditional inner add row is appended instead of inlined.
  local zoneMode = isDone and "done" or (flowKey or groupMode)
  -- Flow/Done zones carry no key (the mode names the column); tag modes encode
  -- their bucket key.
  local zoneKey = (isDone or flowKey ~= nil) and "" or colId
  local kids = { columnHeader(g, isDone, flowKey) }
  if addCol == colId and not isDone then
    kids[#kids + 1] = columnAddRow(g, colId, flowKey)
  end
  kids[#kids + 1] = ui.dropZone({
    key = "zone-" .. colId,
    accepts = { "kanban-task" },
    value = "dz:" .. zoneMode .. ":" .. zoneKey,
    onDrop = handleDrop,
    direction = "column",
    expandOnDrag = true,
    enabled = not busy,
    flexGrow = 1,
  }, {
    ui.scroll({ key = "body-" .. colId, gap = 4, flexGrow = 1 }, cards),
  })

  return ui.column({
    key = "col-" .. colId,
    minWidth = 150,
    gap = 6,
    flexGrow = 1,
    fill = isDone and "surface_variant/0.15" or "surface_variant/0.28",
    radius = 10,
    padding = 8,
  }, kids)
end

local function board()
  local pending = pendingTasks()
  local done = doneTasks()

  if groupMode == "flow" then
    local todo, doing = {}, {}
    for _, t in ipairs(pending) do
      if hasDoing(t) then doing[#doing + 1] = t else todo[#todo + 1] = t end
    end
    return ui.row({ key = "board", gap = 8, align = "stretch", flexGrow = 1 }, {
      boardColumn({ key = "\0todo", label = "", color = nil, items = todo }, false, "todo"),
      boardColumn({ key = "\0doing", label = "", color = nil, items = doing }, false, "doing"),
      boardColumn({ key = "\0none", label = "", color = nil, items = done }, true),
    })
  end

  local groups = note.group(pending, groupMode)

  local cols = {}
  for _, g in ipairs(groups) do
    cols[#cols + 1] = boardColumn(g, false)
  end
  cols[#cols + 1] = boardColumn({ key = "\0none", label = "", color = nil, items = done }, true)

  return ui.row({ key = "board", gap = 8, align = "stretch", flexGrow = 1 }, cols)
end

-- ── Header / controls ─────────────────────────────────────────────────────────

local function header()
  local nodes = {}
  local function add(n) if n ~= nil then nodes[#nodes + 1] = n end end

  add(ui.glyph({ name = "layout-kanban", size = 15, color = "primary" }))
  add(ui.label({ text = noctalia.tr("ui.kanban.title"), fontSize = 15, fontWeight = "bold", color = "on_surface" }))
  if counts ~= nil then
    add(ui.label({
      text = noctalia.tr("ui.summary", { pending = counts.pending or 0, overdue = counts.overdue or 0 }),
      fontSize = 11,
      color = (counts.overdue or 0) > 0 and note.COLOR.overdue or "on_surface_variant",
    }))
  end
  add(ui.spacer({ flexGrow = 1 }))
  if busy or polling then
    add(ui.glyph({ name = "loader", size = 13, color = "on_surface_variant" }))
  end
  add(ui.button({
    glyph = "refresh",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.refresh"),
    enabled = not polling,
    onClick = function() request({ action = "refresh" }) end,
  }))
  add(ui.button({
    glyph = "terminal-2",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.open_tui"),
    onClick = function() noctalia.runInTerminal(note.shellCmd({})) end,
  }))
  add(ui.button({
    glyph = "list",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.kanban.open_list"),
    onClick = function() noctalia.togglePanel("gery/note-tuxedo:todo-panel") end,
  }))
  return ui.row({ gap = 8, align = "center", paddingH = 4 }, nodes)
end

local function controls()
  local modes = { "flow", "project", "priority", "context", "none" }
  local modeLabel = {
    flow = "ui.group_by.flow",
    project = "ui.group_by.project",
    priority = "ui.group_by.priority",
    context = "ui.group_by.context",
    none = "ui.group_by.none",
  }
  local groupButtons = { ui.label({ text = noctalia.tr("ui.group_by"), fontSize = 11, color = "on_surface_variant" }) }
  for _, m in ipairs(modes) do
    groupButtons[#groupButtons + 1] = ui.button({
      text = noctalia.tr(modeLabel[m]),
      variant = groupMode == m and "primary" or "outline",
      controlSize = "sm",
      selected = groupMode == m,
      onClick = function()
        groupMode = m
        -- Column ids change with the mode: a seeded add row must not carry
        -- tokens written for the previous mode.
        addCol = nil
        addColText = ""
        render()
      end,
    })
  end

  return ui.column({ gap = 6 }, {
    ui.row({ gap = 6, align = "center", paddingH = 4 }, groupButtons),
    ui.row({ gap = 6, align = "center", paddingH = 4 }, {
      ui.input({
        key = "search",
        placeholder = noctalia.tr("ui.search_placeholder"),
        flexGrow = 1,
        controlSize = "sm",
        onChange = function(v) search = v or ""; render() end,
      }),
    }),
  })
end

local function errorBanner()
  local nodes = {
    ui.glyph({ name = "alert-circle", size = 13, color = "error" }),
    ui.label({
      text = noctalia.tr("ui.error." .. failure.code),
      fontSize = 11,
      color = "error",
      flexGrow = 1,
      maxLines = 1,
    }),
    ui.button({
      text = noctalia.tr("ui.retry"),
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      enabled = not polling,
      onClick = function() request({ action = "refresh" }) end,
    }),
  }
  if failure.code == "not_installed" then
    nodes[#nodes + 1] = ui.button({
      text = noctalia.tr("ui.settings"),
      glyph = "settings",
      variant = "ghost",
      controlSize = "sm",
      onClick = function() noctalia.openSettings() end,
    })
  end
  return ui.row({ gap = 6, align = "center", paddingH = 4 }, nodes)
end

-- ── Global add row ────────────────────────────────────────────────────────────

local addRowText = ""

local function submitAdd()
  local text = note.trim(addRowText)
  if text ~= "" then request({ action = "add", text = text }) end
  addRowText = ""
  addNonce = addNonce + 1
  render()
end

local function addRow()
  return ui.row({ gap = 6, align = "center", paddingH = 4, paddingV = 2 }, {
    ui.input({
      key = "add-" .. addNonce,
      placeholder = noctalia.tr("ui.add_placeholder"),
      flexGrow = 1,
      submitOnEnter = true,
      onChange = function(v) addRowText = v or "" end,
      onSubmit = function() submitAdd() end,
    }),
    ui.button({
      text = noctalia.tr("ui.add"),
      glyph = "plus",
      variant = "primary",
      controlSize = "sm",
      onClick = function() submitAdd() end,
    }),
  })
end

render = function()
  local children = { header(), controls() }

  if failure.code ~= "" then
    children[#children + 1] = errorBanner()
  end

  if failure.code ~= "" and #tasks == 0 and failure.code == "not_installed" then
    children[#children + 1] = ui.row({ gap = 8, align = "center", paddingH = 8, flexGrow = 1 }, {
      ui.glyph({ name = "info-circle", size = 16, color = "on_surface_variant" }),
      ui.label({
        text = noctalia.tr("ui.not_installed_body"),
        fontSize = 12,
        color = "on_surface_variant",
        maxLines = 3,
      }),
    })
    panel.render(ui.column({ gap = 10, padding = 12, flexGrow = 1 }, children))
    return
  end

  children[#children + 1] = board()
  children[#children + 1] = ui.separator({ color = "outline", opacity = 0.2 })
  children[#children + 1] = addRow()

  panel.render(ui.column({ gap = 10, padding = 12, flexGrow = 1 }, children))
end

-- ── Wiring ────────────────────────────────────────────────────────────────────

-- Headless verification:
--   noctalia msg plugin gery/note-tuxedo:todo-kanban all open-board priority
function onIpc(event, payload)
  if event == "open-board" and type(payload) == "string" then
    local g = payload
    if g == "flow" or g == "project" or g == "priority" or g == "context" or g == "none" then
      groupMode = g
      addCol = nil
      addColText = ""
      lastOpenSeq = noctalia.nowMs()
    end
  end
end

local function consumeOpenBoard()
  local ob = noctalia.state.get("openBoard")
  if type(ob) ~= "table" or type(ob.seq) ~= "number" or ob.seq <= lastOpenSeq then return end
  lastOpenSeq = ob.seq
  local g = ob.group
  if g == "flow" or g == "project" or g == "priority" or g == "context" or g == "none" then
    groupMode = g
    addCol = nil
    addColText = ""
  end
end

noctalia.state.watch("tasks", function(value)
  if type(value) == "table" then tasks = value end
  render()
end)

noctalia.state.watch("counts", function(value)
  counts = value
  render()
end)

noctalia.state.watch("error", function(value)
  failure = note.asFailure(value)
  render()
end)

noctalia.state.watch("polling", function(value)
  polling = value == true
  render()
end)

noctalia.state.watch("busy", function(value)
  busy = value == true
  render()
end)

noctalia.state.watch("openBoard", function()
  consumeOpenBoard()
  render()
end)

function onOpen(_context)
  noctalia.state.set("boardOpen", true)
  tasks = noctalia.state.get("tasks") or {}
  counts = noctalia.state.get("counts")
  failure = note.asFailure(noctalia.state.get("error"))
  polling = noctalia.state.get("polling") == true
  busy = noctalia.state.get("busy") == true
  consumeOpenBoard()
  request({ action = "refresh" })
  render()
end

function onClose()
  noctalia.state.set("boardOpen", false)
end

tasks = noctalia.state.get("tasks") or {}
counts = noctalia.state.get("counts")
failure = note.asFailure(noctalia.state.get("error"))
consumeOpenBoard()
render()
