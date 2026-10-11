--!nonstrict
-- Shared helpers for the gery/note-tuxedo plugin: settings, binary resolution,
-- the `env`-wrapped tuxedo argv builder, and task grouping/counting. Required by
-- the service, widget, panel and launcher so they cannot disagree on screen.
-- Needs plugin_api 22 (require) and 24 (argv tables for runAsync).

local M = {}

M.COLOR = {
  priA     = "#f38ba8",
  priB     = "#fab387",
  priC     = "#f9e2af",
  priOther = "#94e2d5",
  project  = "#89b4fa",
  context  = "#a6e3a1",
  due      = "#94e2d5",
  overdue  = "#f38ba8",
  today    = "#f9e2af",
  done     = "#6c7086",
  ok       = "#4ade80",
  error    = "#f87171",
}

local PRI_TINT = { A = M.COLOR.priA, B = M.COLOR.priB, C = M.COLOR.priC }

function M.priorityColor(pri)
  if pri == nil or pri == "" then return "on_surface_variant" end
  return PRI_TINT[pri] or M.COLOR.priOther
end

-- Shared "no failure" sentinel, so every entry reads the same empty slot.
M.NO_FAILURE = { code = "", detail = "" }

function M.asFailure(value)
  if type(value) ~= "table" then return M.NO_FAILURE end
  return {
    code = type(value.code) == "string" and value.code or "",
    detail = type(value.detail) == "string" and value.detail or "",
  }
end

function M.cfg(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v
end

function M.trim(s)
  return noctalia.string.trim(tostring(s or ""))
end

-- Resolve a bare name to an absolute path. The plugin subprocess does not
-- reliably inherit the session PATH (a bare name fails with "command not
-- found"), so walk the session PATH ourselves. Absolute paths and ~ paths are
-- honoured as-is for a hard override.
function M.expandBinary(binary)
  binary = M.trim(binary)
  if binary == "" then return "tuxedo" end
  if binary:sub(1, 1) == "/" then return binary end
  local asPath = noctalia.expandPath(binary)
  if asPath and noctalia.fileExists(asPath) then return asPath end
  local envPath = noctalia.getenv("PATH") or ""
  for dir in (envPath .. ":"):gmatch("([^:]*):") do
    if #dir > 0 then
      local candidate = dir .. "/" .. binary
      if noctalia.fileExists(candidate) then return candidate end
    end
  end
  return binary
end

local function absoluteSetting(key)
  local v = M.trim(M.cfg(key, ""))
  if v == "" then return nil end
  return noctalia.expandPath(v) or v
end

-- Full argv for a tuxedo invocation, with the TODO_* environment injected:
--   env [TODO_DIR=…] [TODO_FILE=…] [DONE_FILE=…] [NOTES_DIR=…] <tuxedo> <args…>
-- The argv-table form (API 24) is exec'd directly — no shell, so free text in
-- `args` needs no quoting at all.
function M.argv(args)
  local out = { M.expandBinary("env") }
  local dir = absoluteSetting("todo_dir")
  local file = absoluteSetting("todo_file")
  local done = absoluteSetting("done_file")
  local notes = absoluteSetting("notes_dir")
  if dir then out[#out + 1] = "TODO_DIR=" .. dir end
  if file then out[#out + 1] = "TODO_FILE=" .. file end
  if done then out[#out + 1] = "DONE_FILE=" .. done end
  if notes then out[#out + 1] = "NOTES_DIR=" .. notes end
  out[#out + 1] = M.expandBinary(M.cfg("tuxedo_binary", "tuxedo"))
  for _, a in ipairs(args) do out[#out + 1] = a end
  return out
end

local function shq(v)
  return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

-- The same command as a single shell string, for runInTerminal (the TUI).
function M.shellCmd(args)
  local parts = {}
  for _, a in ipairs(M.argv(args)) do parts[#parts + 1] = shq(a) end
  return table.concat(parts, " ")
end

-- ── Dates ─────────────────────────────────────────────────────────────────────

function M.today()
  return os.date("%Y-%m-%d")
end

function M.isOverdue(t)
  return t ~= nil and not t.done and t.due ~= nil and t.due ~= "" and t.due < M.today()
end

function M.isDueToday(t)
  return t ~= nil and not t.done and t.due == M.today()
end

-- ── Counting ──────────────────────────────────────────────────────────────────

function M.summarize(tasks)
  local s = {
    total = 0,
    pending = 0,
    done = 0,
    overdue = 0,
    due_today = 0,
    by_priority = { A = 0, B = 0, C = 0, other = 0, none = 0 },
    projects = {},
    contexts = {},
  }
  for _, t in ipairs(tasks or {}) do
    s.total = s.total + 1
    if t.done then
      s.done = s.done + 1
    else
      s.pending = s.pending + 1
      local p = t.priority
      if p == nil or p == "" then
        s.by_priority.none = s.by_priority.none + 1
      elseif p == "A" or p == "B" or p == "C" then
        s.by_priority[p] = s.by_priority[p] + 1
      else
        s.by_priority.other = s.by_priority.other + 1
      end
      if M.isOverdue(t) then s.overdue = s.overdue + 1 end
      if M.isDueToday(t) then s.due_today = s.due_today + 1 end
    end
    for _, pr in ipairs(t.projects or {}) do
      s.projects[pr] = (s.projects[pr] or 0) + 1
    end
    for _, c in ipairs(t.contexts or {}) do
      s.contexts[c] = (s.contexts[c] or 0) + 1
    end
  end
  return s
end

function M.sortedKeys(map)
  local keys = {}
  for k in pairs(map or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return a:lower() < b:lower() end)
  return keys
end

-- ── Grouping (panel view) ─────────────────────────────────────────────────────

local NONE_KEY = "\0none"

local function firstOf(list)
  if type(list) == "table" and #list > 0 then return list[1] end
  return nil
end

-- Returns an ordered array of { key, label, color, items } buckets. `tasks`
-- must already be filtered (e.g. done hidden) by the caller.
function M.group(tasks, mode)
  if mode == "project" or mode == "context" then
    local isProject = mode == "project"
    local field = isProject and "projects" or "contexts"
    local color = isProject and M.COLOR.project or M.COLOR.context
    local sigil = isProject and "+" or "@"
    local order, map = {}, {}
    local function put(key, label)
      local b = map[key]
      if b == nil then
        b = { key = key, label = label, color = color, items = {} }
        map[key] = b
        order[#order + 1] = b
      end
      return b
    end
    for _, t in ipairs(tasks) do
      local name = firstOf(t[field])
      if name == nil then
        put(NONE_KEY, noctalia.tr(isProject and "ui.no_project" or "ui.no_context")).items[#map[NONE_KEY].items + 1] = t
      else
        put(name, sigil .. name).items[#map[name].items + 1] = t
      end
    end
    table.sort(order, function(a, b)
      if a.key == NONE_KEY then return false end
      if b.key == NONE_KEY then return true end
      return a.key:lower() < b.key:lower()
    end)
    return order
  end

  if mode == "priority" then
    local present = {}
    for _, t in ipairs(tasks) do
      local p = t.priority
      if p ~= nil and p ~= "" then present[p] = true end
    end
    local keys = M.sortedKeys(present)
    local order, map = {}, {}
    local none = { key = NONE_KEY, label = noctalia.tr("ui.no_priority"), color = "on_surface_variant", items = {} }
    for _, p in ipairs(keys) do
      map[p] = {
        key = p,
        label = noctalia.tr("ui.priority", { p = p }),
        color = M.priorityColor(p),
        items = {},
      }
      order[#order + 1] = map[p]
    end
    order[#order + 1] = none
    for _, t in ipairs(tasks) do
      local p = t.priority
      if p == nil or p == "" then
        none.items[#none.items + 1] = t
      else
        map[p].items[#map[p].items + 1] = t
      end
    end
    return order
  end

  return { { key = "all", label = "", color = nil, items = tasks } }
end

return M
