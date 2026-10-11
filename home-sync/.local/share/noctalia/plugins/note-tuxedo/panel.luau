--!nonstrict
-- Panel: the tuxedo frontend. Reads the task list the service publishes and
-- groups it by project, context or priority; every action becomes a request the
-- service turns into a `tuxedo` CLI call. Needs plugin_api 22 (require) and 24.

local note = require("./lib/note.luau")

local MODES = { "priority", "project", "context", "none" }
local MODE_LABELS = {
  priority = "ui.group_by.priority",
  project = "ui.group_by.project",
  context = "ui.group_by.context",
  none = "ui.group_by.none",
}

local tasks = {}
local counts = nil
local failure = note.NO_FAILURE
local polling = false
local busy = false

local groupMode = note.cfg("default_group_by", "priority")
if MODE_LABELS[groupMode] == nil then groupMode = "priority" end
local search = ""
local showDone = false
local projFilter = nil
local ctxFilter = nil
local addNonce = 0
local draftText = ""
-- The task number currently being edited inline (nil = none), and the buffer
-- the edit field reports through onChange.
local editingN = nil
local editText = ""

local render -- forward declaration

-- ── Requests to the service ───────────────────────────────────────────────────

local reqSeq = 0
local function request(tbl)
  -- Monotonic wall clock, so the service can order requests across VMs (the
  -- launcher sends through the same channel).
  local seq = noctalia.nowMs()
  if seq <= reqSeq then seq = reqSeq + 0.001 end
  reqSeq = seq
  tbl.seq = seq
  noctalia.state.set("request", tbl)
end

-- ── Filtering & sorting ───────────────────────────────────────────────────────

local function hasValue(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

local function priorityRank(p)
  if p == nil or p == "" then return "ZZZ" end
  return p
end

local function compare(a, b)
  if a.done ~= b.done then return not a.done end
  if a.priority ~= b.priority then return priorityRank(a.priority) < priorityRank(b.priority) end
  local ad = a.due ~= nil and a.due ~= "" and a.due or "9999-99-99"
  local bd = b.due ~= nil and b.due ~= "" and b.due or "9999-99-99"
  if ad ~= bd then return ad < bd end
  return a.n < b.n
end

local function visibleTasks()
  local out = {}
  local needle = search:lower()
  for _, t in ipairs(tasks) do
    local ok = showDone or not t.done
    if ok and projFilter ~= nil and not hasValue(t.projects, projFilter) then ok = false end
    if ok and ctxFilter ~= nil and not hasValue(t.contexts, ctxFilter) then ok = false end
    if ok and needle ~= "" and not t.raw:lower():find(needle, 1, true) then ok = false end
    if ok then out[#out + 1] = t end
  end
  table.sort(out, compare)
  return out
end

-- ── Row builders ──────────────────────────────────────────────────────────────

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

local function openEdit(t)
  editingN = t.n
  editText = t.raw
  render()
end

local function editRow(t)
  return ui.row({
    key = "task-" .. t.n,
    gap = 6,
    align = "center",
    paddingH = 6,
    paddingV = 2,
    radius = 6,
    fill = "surface_variant/0.35",
  }, {
    ui.input({
      key = "edit-input-" .. t.n,
      value = t.raw,
      flexGrow = 1,
      fontSize = 12,
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

local function taskRow(t)
  if editingN == t.n then return editRow(t) end

  local nodes = {}
  local function add(node) if node ~= nil then nodes[#nodes + 1] = node end end

  add(ui.toggle({
    checked = t.done,
    key = "tgl-" .. t.n,
    onChange = function() request({ action = "toggle", n = t.n }) end,
  }))

  add(ui.button({
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
  }))

  add(ui.row({
    key = "txt-" .. t.n,
    flexGrow = 1,
    align = "center",
    onClick = function() openEdit(t) end,
  }, {
    ui.label({
      text = t.raw,
      fontSize = 12,
      color = t.done and note.COLOR.done or "on_surface",
      flexGrow = 1,
      maxLines = 2,
    }),
  }))

  if t.due ~= nil and t.due ~= "" then
    add(ui.row({ gap = 2, align = "center" }, {
      ui.glyph({ name = "calendar-event", size = 11, color = dueColor(t) }),
      ui.label({ text = t.due, fontSize = 10, color = dueColor(t), maxLines = 1 }),
    }))
  end

  for _, p in ipairs(t.projects) do
    add(ui.button({
      text = "+" .. p,
      variant = "ghost",
      controlSize = "sm",
      onClick = function() projFilter = p; render() end,
    }))
  end
  for _, c in ipairs(t.contexts) do
    add(ui.button({
      text = "@" .. c,
      variant = "ghost",
      controlSize = "sm",
      onClick = function() ctxFilter = c; render() end,
    }))
  end

  add(ui.button({
    key = "edit-" .. t.n,
    glyph = "pencil",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.edit"),
    onClick = function() openEdit(t) end,
  }))
  add(ui.button({
    key = "del-" .. t.n,
    glyph = "trash",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.delete"),
    onClick = function() request({ action = "delete", n = t.n }) end,
  }))

  return ui.row({
    key = "task-" .. t.n,
    gap = 6,
    align = "center",
    paddingH = 6,
    paddingV = 2,
    radius = 6,
  }, nodes)
end

local function groupHeader(g)
  local children = {
    ui.label({ text = g.label, fontSize = 11, fontWeight = "semibold", color = g.color or "on_surface_variant" }),
    ui.label({ text = "(" .. tostring(#g.items) .. ")", fontSize = 10, color = "on_surface_variant" }),
    ui.spacer({ flexGrow = 1 }),
    ui.box({ height = 1, fill = "outline/0.18", flexGrow = 1 }),
  }
  return ui.row({ key = "grp-" .. g.key, gap = 6, align = "center", paddingH = 4 }, children)
end

-- ── Header / controls ─────────────────────────────────────────────────────────

local function header()
  local nodes = {}
  local function add(n) if n ~= nil then nodes[#nodes + 1] = n end end

  add(ui.glyph({ name = "list-check", size = 15, color = "primary" }))
  add(ui.label({ text = noctalia.tr("ui.title"), fontSize = 15, fontWeight = "bold", color = "on_surface" }))
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
    text = noctalia.tr("ui.open_tui"),
    glyph = "terminal-2",
    variant = "secondary",
    controlSize = "sm",
    onClick = function() noctalia.runInTerminal(note.shellCmd({})) end,
  }))
  return ui.row({ gap = 8, align = "center", paddingH = 4 }, nodes)
end

local function controls()
  local groupButtons = { ui.label({ text = noctalia.tr("ui.group_by"), fontSize = 11, color = "on_surface_variant" }) }
  for _, m in ipairs(MODES) do
    groupButtons[#groupButtons + 1] = ui.button({
      text = noctalia.tr(MODE_LABELS[m]),
      variant = groupMode == m and "primary" or "outline",
      controlSize = "sm",
      selected = groupMode == m,
      onClick = function() groupMode = m; render() end,
    })
  end

  local activeFilters = {}
  if projFilter ~= nil then
    activeFilters[#activeFilters + 1] = ui.button({
      text = "+" .. projFilter,
      glyph = "x",
      variant = "secondary",
      controlSize = "sm",
      onClick = function() projFilter = nil; render() end,
    })
  end
  if ctxFilter ~= nil then
    activeFilters[#activeFilters + 1] = ui.button({
      text = "@" .. ctxFilter,
      glyph = "x",
      variant = "secondary",
      controlSize = "sm",
      onClick = function() ctxFilter = nil; render() end,
    })
  end

  local rows = {
    ui.row({ gap = 6, align = "center", paddingH = 4 }, groupButtons),
    ui.row({ gap = 6, align = "center", paddingH = 4 }, {
      ui.input({
        key = "search",
        placeholder = noctalia.tr("ui.search_placeholder"),
        flexGrow = 1,
        controlSize = "sm",
        onChange = function(v) search = v or ""; render() end,
      }),
      ui.label({ text = noctalia.tr("ui.show_done"), fontSize = 11, color = "on_surface_variant" }),
      ui.toggle({
        checked = showDone,
        onChange = function(v) showDone = (v == "true"); render() end,
      }),
    }),
  }
  if #activeFilters > 0 then
    local filterRow = { ui.label({ text = noctalia.tr("ui.filters"), fontSize = 11, color = "on_surface_variant" }) }
    for _, b in ipairs(activeFilters) do filterRow[#filterRow + 1] = b end
    rows[#rows + 1] = ui.row({ gap = 6, align = "center", paddingH = 4 }, filterRow)
  end
  return ui.column({ gap = 6 }, rows)
end

local function addRow()
  return ui.row({ gap = 6, align = "center", paddingH = 4, paddingV = 2 }, {
    ui.input({
      key = "add-" .. addNonce,
      placeholder = noctalia.tr("ui.add_placeholder"),
      flexGrow = 1,
      submitOnEnter = true,
      onChange = function(v) draftText = v or "" end,
      onSubmit = function()
        local text = note.trim(draftText)
        if text == "" then return end
        request({ action = "add", text = text })
        draftText = ""
        addNonce = addNonce + 1
        render()
      end,
    }),
    ui.button({
      text = noctalia.tr("ui.add"),
      glyph = "plus",
      variant = "primary",
      controlSize = "sm",
      onClick = function()
        local text = note.trim(draftText)
        if text == "" then return end
        request({ action = "add", text = text })
        draftText = ""
        addNonce = addNonce + 1
        render()
      end,
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

-- ── Render ────────────────────────────────────────────────────────────────────

render = function()
  local children = { header(), controls() }

  if failure.code ~= "" then
    children[#children + 1] = errorBanner()
  end

  if failure.code ~= "" and #tasks == 0 and failure.code == "not_installed" then
    -- Nothing to show and the binary is missing: say so rather than an empty list.
    children[#children + 1] = ui.row({ gap = 8, align = "center", paddingH = 8, flexGrow = 1 }, {
      ui.glyph({ name = "info-circle", size = 16, color = "on_surface_variant" }),
      ui.label({ text = noctalia.tr("ui.not_installed_body"), fontSize = 12, color = "on_surface_variant", maxLines = 3 }),
    })
    panel.render(ui.column({ gap = 10, padding = 14, flexGrow = 1 }, children))
    return
  end

  local visible = visibleTasks()
  local list = {}
  if #visible == 0 then
    list[#list + 1] = ui.row({ gap = 6, align = "center", paddingH = 8, paddingV = 10 }, {
      ui.glyph({ name = "checks", size = 15, color = "on_surface_variant" }),
      ui.label({ text = noctalia.tr("ui.empty"), fontSize = 12, color = "on_surface_variant" }),
    })
  else
    local groups = note.group(visible, groupMode)
    for _, g in ipairs(groups) do
      if groupMode ~= "none" and g.label ~= "" then
        list[#list + 1] = groupHeader(g)
      end
      for _, t in ipairs(g.items) do
        list[#list + 1] = taskRow(t)
      end
    end
  end

  children[#children + 1] = ui.scroll({ gap = 2, flexGrow = 1 }, list)
  children[#children + 1] = ui.separator({ color = "outline", opacity = 0.2 })
  children[#children + 1] = addRow()

  panel.render(ui.column({ gap = 10, padding = 14, flexGrow = 1 }, children))
end

-- ── Wiring ────────────────────────────────────────────────────────────────────

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

function onOpen(_context)
  tasks = noctalia.state.get("tasks") or {}
  counts = noctalia.state.get("counts")
  failure = note.asFailure(noctalia.state.get("error"))
  polling = noctalia.state.get("polling") == true
  busy = noctalia.state.get("busy") == true
  request({ action = "refresh" })
  render()
end

tasks = noctalia.state.get("tasks") or {}
counts = noctalia.state.get("counts")
failure = note.asFailure(noctalia.state.get("error"))
render()
