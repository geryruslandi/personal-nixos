--!nonstrict
-- Shared helpers for gery/notes-md: config, path/name rules, UI-state
-- persistence, binary lookup and index lookups. Required by every entry so
-- the service, panel, launcher and widget agree on paths and settings.
-- Needs plugin_api 22 (require).

local M = {}

M.PANEL_ID = "gery/notes-md:notes-panel"
M.DEFAULT_ROOT = "~/Documents"
M.INDEX_KEY = "notes_md_index"
M.BUMP_KEY = "notes_md_bump"
M.SCAN_KEY = "notes_md_scan_request"
M.OPEN_KEY = "notes_md_open"
M.NEW_KEY = "notes_md_new"
M.PANEL_OPEN_KEY = "notes_md_panel_open"

M.DEFAULT_IGNORED = {
  "node_modules", ".git", ".svn", ".hg", "venv", ".venv", "__pycache__",
  "target", "dist", "build", "out", ".cache", ".direnv", ".nix",
}

M.SPACE_COLORS = {
  "#89b4fa", "#a6e3a1", "#f9e2af", "#fab387",
  "#cba6f7", "#94e2d5", "#f38ba8", "#b4befe",
}

function M.cfg(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v
end

function M.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local suffixRaw = nil
local suffixValue = ".md"

function M.suffix()
  local raw = M.trim(M.cfg("extension", "md"))
  if raw == suffixRaw then return suffixValue end
  local ext = raw:gsub("^%.", "")
  if ext == "" then ext = "md" end
  suffixRaw = raw
  suffixValue = "." .. ext
  return suffixValue
end

function M.root()
  local dir = M.trim(M.cfg("notes_dir", M.DEFAULT_ROOT))
  if dir == "" then dir = M.DEFAULT_ROOT end
  return noctalia.expandPath(dir)
end

local ignoredRaw = nil
local ignoredValue = nil

function M.ignored()
  local raw = M.trim(M.cfg("ignored_dirs", ""))
  if raw == ignoredRaw and ignoredValue ~= nil then return ignoredValue end
  local out = {}
  if raw == "" then
    out = M.DEFAULT_IGNORED
  else
    for item in (raw .. ","):gmatch("([^,]*),") do
      local name = M.trim(item)
      if name ~= "" then out[#out + 1] = name end
    end
  end
  ignoredRaw = raw
  ignoredValue = out
  return out
end

function M.isIgnored(name)
  for _, needle in ipairs(M.ignored()) do
    if name == needle then return true end
  end
  return false
end

function M.norm(rel)
  rel = tostring(rel or ""):gsub("^/+", ""):gsub("/+$", "")
  rel = rel:gsub("/+", "/")
  return rel
end

function M.path(root, rel)
  rel = M.norm(rel)
  if rel == "" then return root end
  return root .. "/" .. rel
end

function M.parent(rel)
  rel = M.norm(rel)
  local p = rel:match("^(.*)/[^/]+$")
  return p or ""
end

function M.base(rel)
  rel = M.norm(rel)
  return rel:match("([^/]+)$") or rel
end

function M.spaceOf(rel)
  rel = M.norm(rel)
  return rel:match("^([^/]+)") or ""
end

-- Space of an indexed entry: a top-level directory is its own space, a
-- top-level note belongs to no space (Loose), anything deeper belongs to its
-- first path component.
function M.entrySpace(rel, isDir)
  rel = M.norm(rel)
  if M.parent(rel) == "" then
    return isDir and rel or ""
  end
  return M.spaceOf(rel)
end

function M.stem(name)
  local suffix = M.suffix()
  if #name > #suffix and name:sub(-#suffix):lower() == suffix:lower() then
    return name:sub(1, #name - #suffix)
  end
  return name
end

function M.isNote(name)
  local suffix = M.suffix()
  return #name > #suffix
    and name:sub(-#suffix):lower() == suffix:lower()
    and name:sub(1, 1) ~= "."
end

function M.isUnder(rel, prefix)
  if prefix == "" then return true end
  return rel == prefix or rel:sub(1, #prefix + 1) == prefix .. "/"
end

function M.ancestors(rel)
  local out = {}
  local cur = M.parent(rel)
  while cur ~= "" do
    table.insert(out, 1, cur)
    cur = M.parent(cur)
  end
  return out
end

-- Reject traversal and characters that cannot be a single path component.
function M.sanitize(name)
  name = M.trim(name)
  name = name:gsub("[%c/\\]", " ")
  name = name:gsub("^%.+", "")
  name = name:gsub("%s+$", "")
  name = M.trim(name)
  if name == "" or name == "." or name == ".." then return "" end
  if #name > 120 then name = name:sub(1, 120) end
  return name
end

function M.uniqueRel(root, parentRel, base)
  local parentRelN = M.norm(parentRel)
  local suffix = M.suffix()
  local rel = (parentRelN == "") and (base .. suffix) or (parentRelN .. "/" .. base .. suffix)
  local counter = 2
  while noctalia.fileExists(M.path(root, rel)) do
    local candidate = base .. " (" .. counter .. ")"
    rel = (parentRelN == "") and (candidate .. suffix) or (parentRelN .. "/" .. candidate .. suffix)
    counter += 1
  end
  return rel
end

function M.uniqueDirRel(root, parentRel, base)
  local parentRelN = M.norm(parentRel)
  local rel = (parentRelN == "") and base or (parentRelN .. "/" .. base)
  local counter = 2
  while noctalia.fileExists(M.path(root, rel)) do
    rel = (parentRelN == "") and (base .. " (" .. counter .. ")")
      or (parentRelN .. "/" .. base .. " (" .. counter .. ")")
    counter += 1
  end
  return rel
end

function M.relative(root, absolute)
  absolute = tostring(absolute or "")
  if absolute == root then return "" end
  if absolute:sub(1, #root + 1) == root .. "/" then
    return absolute:sub(#root + 2)
  end
  return nil
end

function M.spaceColor(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 1000003 end
  return M.SPACE_COLORS[(h % #M.SPACE_COLORS) + 1]
end

function M.expandBinary(binary)
  binary = M.trim(binary)
  if binary == "" then return binary end
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

-- ── UI state (persisted outside the notes tree) ──────────────────────────────

local function statePath()
  local dir = noctalia.pluginDataDir()
  if dir == nil then return nil end
  return dir .. "/ui-state.json"
end

function M.readUiState()
  local path = statePath()
  if path == nil then return {} end
  local raw = noctalia.readFile(path)
  if raw == nil or raw == "" then return {} end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then return {} end
  return decoded
end

function M.writeUiState(state)
  local path = statePath()
  if path == nil then return false end
  local encoded = noctalia.json.encode(state)
  if encoded == nil then return false end
  return noctalia.writeFile(path, encoded)
end

-- ── Cross-entry notifications ────────────────────────────────────────────────

-- Publish a fresh index generation. The service stamps each scan with the
-- generation it started from; the panel ignores snapshots older than its last
-- mutation so an in-flight scan cannot clobber a just-renamed/moved note.
function M.bump()
  local n = noctalia.state.get(M.BUMP_KEY)
  local nextValue = (type(n) == "number" and n or 0) + 1
  noctalia.state.set(M.BUMP_KEY, nextValue)
  return nextValue
end

function M.requestScan()
  noctalia.state.set(M.SCAN_KEY, noctalia.nowMs())
  M.bump()
end

-- ── Index helpers ────────────────────────────────────────────────────────────

function M.countNotes(entries)
  local n = 0
  for _, e in ipairs(entries or {}) do
    if e.dir ~= true then n += 1 end
  end
  return n
end

function M.byRel(entries)
  local out = {}
  for _, e in ipairs(entries or {}) do out[e.rel] = e end
  return out
end

function M.cloneEntries(entries)
  local out = {}
  for _, e in ipairs(entries or {}) do out[#out + 1] = e end
  return out
end

return M
