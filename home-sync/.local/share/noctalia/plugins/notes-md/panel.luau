--!nonstrict
-- Notes panel for gery/notes-md.
--
-- Zen-style spaces rail (top-level folders of notes_dir) + folder/note tree +
-- markdown editor with a debounced live preview. The index service publishes
-- the file tree; this entry owns every filesystem mutation (create, rename,
-- move, delete) and bumps the index afterwards.
--
-- Performance rules:
--   * onChange never renders. It only records the buffer and schedules work.
--   * Preview and autosave are flushed from onFrameTick after an idle delay.
--   * The editor input is uncontrolled: `value` is only passed when its key
--     changes (note opened, external reload), never while typing.

local notes = require("./lib/notes.luau")

local PREVIEW_DEBOUNCE_MS = 220
local AUTOSAVE_DEBOUNCE_MS = 800
local SEARCH_DEBOUNCE_MS = 120
local UI_STATE_DEBOUNCE_MS = 1800
local MAX_NOTE_BYTES = 2 * 1024 * 1024
local MAX_PREVIEW_BYTES = 1024 * 1024
local MAX_SEARCH_RESULTS = 150
local SPLIT_PREVIEW_WIDTH = 400
local FULL_PREVIEW_WIDTH = 820
local SIDEBAR_WIDTH = 330
local LOOSE = "__loose"

local root = ""
local suffix = ".md"
local entries = {}
local indexError = nil
local truncated = false
local lastMutationSeq = 0

local byRel = {}
local dirsByParent = {}
local notesByParent = {}
local spaces = {}
local spaceSet = {}
local spaceCounts = {}
local folderCounts = {}
local rootNoteCount = 0

local currentSpace = nil
local selectedDir = ""
local expanded = {}
local openRel = nil
local buffer = ""
local loadedContent = ""
local dirty = false
local editorSeed = 0
local lastEditorKey = nil
local previewMode = "split"
local sortMode = "name"

local query = ""
local querySeeded = false
local searchDue = 0

local prompt = nil
local promptNonce = 0
local promptSeedKey = nil

local movePicker = false
local isOpen = false
local pendingOpenRel = nil
local restoreRel = nil

local duePreview = 0
local dueSave = 0
local dueState = 0

local render -- forward declaration
local openNote -- forward declaration
local clearEditor -- forward declaration

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function cfgPreviewMode()
  local v = noctalia.getConfig("preview_mode")
  if v == "split" or v == "edit" or v == "preview" then return v end
  return "split"
end

local function cfgSortMode()
  local v = noctalia.getConfig("sort_notes")
  if v == "modified" then return "modified" end
  return "name"
end

local function notifyError(message)
  noctalia.notifyError(tr("ui.title"), message or "")
end

local function displayRel(rel)
  if rel == nil or rel == "" then return tr("ui.loose") end
  local parts = {}
  for part in (rel .. "/"):gmatch("([^/]*)/") do
    if part ~= "" then parts[#parts + 1] = part end
  end
  return table.concat(parts, " / ")
end

local function displayNotePath(rel)
  local parent = notes.parent(rel)
  local stem = notes.stem(notes.base(rel))
  if parent == "" then return stem end
  return displayRel(parent) .. " / " .. stem
end

local function entrySpace(rel, isDir)
  return notes.entrySpace(rel, isDir)
end

-- ── View model ──────────────────────────────────────────────────────────────

local function sortEntries(list)
  table.sort(list, function(a, b)
    if sortMode == "modified" and a.mtime ~= b.mtime then
      return (a.mtime or 0) > (b.mtime or 0)
    end
    return a.name:lower() < b.name:lower()
  end)
end

local function rebuild()
  byRel = {}
  dirsByParent = {}
  notesByParent = {}
  spaces = {}
  spaceSet = {}
  spaceCounts = {}
  folderCounts = {}
  rootNoteCount = 0

  for _, e in ipairs(entries) do
    byRel[e.rel] = e
    if e.parent == "" and e.dir then
      spaces[#spaces + 1] = e.rel
      spaceSet[e.rel] = true
      spaceCounts[e.rel] = spaceCounts[e.rel] or 0
    elseif e.parent == "" then
      rootNoteCount += 1
    end

    local parent = e.parent or ""
    local bucket = e.dir and dirsByParent or notesByParent
    local list = bucket[parent]
    if list == nil then list = {}; bucket[parent] = list end
    list[#list + 1] = e

    if not e.dir then
      local space = e.space or ""
      if space ~= "" then
        spaceCounts[space] = (spaceCounts[space] or 0) + 1
      end
      local a = parent
      while a ~= "" do
        folderCounts[a] = (folderCounts[a] or 0) + 1
        a = notes.parent(a)
      end
    end
  end

  table.sort(spaces, function(a, b) return a:lower() < b:lower() end)
  for _, list in pairs(dirsByParent) do sortEntries(list) end
  for _, list in pairs(notesByParent) do sortEntries(list) end

  for rel in pairs(expanded) do
    local e = byRel[rel]
    if e == nil or not e.dir then expanded[rel] = nil end
  end

  if currentSpace == LOOSE and rootNoteCount == 0 then
    currentSpace = spaces[1]
  elseif currentSpace ~= nil and currentSpace ~= LOOSE and not spaceSet[currentSpace] then
    currentSpace = spaces[1]
  end
  if currentSpace == nil then
    currentSpace = spaces[1]
    if currentSpace == nil and rootNoteCount > 0 then currentSpace = LOOSE end
  end

  if selectedDir ~= "" then
    local sel = byRel[selectedDir]
    if sel == nil or not sel.dir then
      selectedDir = (currentSpace == LOOSE) and "" or (currentSpace or "")
    end
  end
  if selectedDir == "" and currentSpace ~= nil and currentSpace ~= LOOSE then
    selectedDir = currentSpace
  end
end

local function markMutation()
  lastMutationSeq = notes.bump()
end

local function ensureEntry(rel)
  if byRel[rel] ~= nil then return true end
  if not noctalia.fileExists(notes.path(root, rel)) then return false end
  entries[#entries + 1] = {
    rel = rel,
    name = notes.base(rel),
    dir = false,
    parent = notes.parent(rel),
    space = entrySpace(rel, false),
    mtime = 0,
  }
  rebuild()
  return true
end

local function ingest(value)
  local newRoot = value.root or root
  if newRoot ~= root then
    root = newRoot
    suffix = notes.suffix()
    clearEditor()
  elseif type(value.triggerSeq) == "number" and value.triggerSeq < lastMutationSeq then
    -- A scan that started before our latest rename/move/delete would clobber
    -- the optimistic view; wait for the scan triggered by that mutation.
    return
  end
  entries = notes.cloneEntries(value.entries)
  indexError = value.error
  truncated = value.truncated == true
  rebuild()

  if openRel ~= nil and byRel[openRel] == nil then
    if not ensureEntry(openRel) then
      openRel = nil
      buffer = ""
      loadedContent = ""
      dirty = false
      editorSeed += 1
    end
  end
  if openRel ~= nil and not dirty then
    -- External edit while the note is open: fold it in when idle.
    local path = notes.path(root, openRel)
    local info = noctalia.fileInfo(path)
    if info ~= nil and (info.size or 0) <= MAX_NOTE_BYTES then
      local content = noctalia.readFile(path)
      if content ~= nil and content ~= loadedContent then
        buffer = content
        loadedContent = content
        editorSeed += 1
      end
    end
  end

  if pendingOpenRel ~= nil and isOpen then
    local target = pendingOpenRel
    pendingOpenRel = nil
    if byRel[target] ~= nil then
      openNote(target)
      return
    end
  end

  if restoreRel ~= nil and isOpen and byRel[restoreRel] ~= nil then
    local target = restoreRel
    restoreRel = nil
    openNote(target)
    return
  end

  if isOpen then render() end
end

-- ── Editor state ────────────────────────────────────────────────────────────

local saveUiState -- forward declaration

local function scheduleSave()
  dueState = noctalia.nowMs() + UI_STATE_DEBOUNCE_MS
  panel.setNeedsFrameTick(true)
end

local function flush()
  if not dirty or openRel == nil then return true end
  local path = notes.path(root, openRel)
  if not noctalia.fileExists(path) then
    dirty = false
    notifyError(tr("ui.note_missing"))
    return false
  end
  local ok, err = noctalia.writeFile(path, buffer)
  if not ok then
    notifyError(err or tr("ui.save_failed"))
    return false
  end
  loadedContent = buffer
  dirty = false
  return true
end

clearEditor = function()
  openRel = nil
  buffer = ""
  loadedContent = ""
  dirty = false
  editorSeed += 1
  duePreview = 0
  dueSave = 0
end

local function expandAncestors(rel)
  for _, ancestor in ipairs(notes.ancestors(rel)) do
    expanded[ancestor] = true
  end
end

openNote = function(rel)
  if rel == nil or rel == "" or rel == openRel then return end
  if byRel[rel] == nil then
    notes.requestScan()
    noctalia.notify(tr("ui.title"), tr("ui.note_missing"))
    return
  end
  flush()
  local path = notes.path(root, rel)
  local info = noctalia.fileInfo(path)
  if info == nil then
    notes.requestScan()
    notifyError(tr("ui.note_missing"))
    return
  end
  if (info.size or 0) > MAX_NOTE_BYTES then
    notifyError(tr("ui.note_too_large", { size = tostring(math.floor(MAX_NOTE_BYTES / 1024 / 1024)) }))
    return
  end
  local content = noctalia.readFile(path)
  if content == nil then
    notifyError(tr("ui.read_failed"))
    return
  end
  openRel = rel
  buffer = content
  loadedContent = content
  dirty = false
  editorSeed += 1
  movePicker = false
  prompt = nil
  promptSeedKey = nil
  duePreview = 0
  dueSave = 0
  expandAncestors(rel)
  local space = entrySpace(rel, false)
  currentSpace = (space == "") and LOOSE or space
  selectedDir = notes.parent(rel)
  if selectedDir == "" and currentSpace ~= LOOSE then selectedDir = currentSpace end
  scheduleSave()
  render()
end

-- ── Local entry mutations (instant UI; service index follows) ───────────────

local function addLocal(rel, isDir, mtime)
  entries[#entries + 1] = {
    rel = rel,
    name = notes.base(rel),
    dir = isDir == true,
    parent = notes.parent(rel),
    space = entrySpace(rel, isDir == true),
    mtime = mtime or os.time(),
  }
  rebuild()
end

local function removeLocalPrefix(prefix)
  local out = {}
  for _, e in ipairs(entries) do
    if not notes.isUnder(e.rel, prefix) then out[#out + 1] = e end
  end
  entries = out
  rebuild()
end

local function renameLocalPrefix(oldRel, newRel)
  for _, e in ipairs(entries) do
    if notes.isUnder(e.rel, oldRel) then
      e.rel = newRel .. e.rel:sub(#oldRel + 1)
      e.name = notes.base(e.rel)
      e.parent = notes.parent(e.rel)
      e.space = entrySpace(e.rel, e.dir == true)
    end
  end
  rebuild()
end

local function noteDestination(targetParent, name)
  if targetParent == nil or targetParent == "" then return name end
  return targetParent .. "/" .. name
end

local function stripSuffix(name)
  if #name > #suffix and name:sub(-#suffix):lower() == suffix:lower() then
    return name:sub(1, #name - #suffix)
  end
  return name
end

-- ── File operations ─────────────────────────────────────────────────────────

local function createNote(parentRel, rawName)
  local name = stripSuffix(notes.sanitize(rawName))
  if name == "" then
    notifyError(tr("ui.invalid_name"))
    return
  end
  local parent = parentRel or ""
  if parent == LOOSE then parent = "" end
  local rel = notes.uniqueRel(root, parent, name)
  local ok, err = noctalia.mkdirAll(notes.path(root, parent))
  if not ok then notifyError(err or tr("ui.create_failed")); return end
  ok, err = noctalia.writeFile(notes.path(root, rel), "")
  if not ok then notifyError(err or tr("ui.create_failed")); return end
  addLocal(rel, false)
  expanded[parent] = true
  markMutation()
  scheduleSave()
  openNote(rel)
end

local function createFolder(parentRel, rawName, asSpace)
  local name = notes.sanitize(rawName)
  if name == "" then
    notifyError(tr("ui.invalid_name"))
    return
  end
  local parent = parentRel or ""
  if parent == LOOSE then parent = "" end
  local rel = notes.uniqueDirRel(root, parent, name)
  local ok, err = noctalia.mkdirAll(notes.path(root, rel))
  if not ok then notifyError(err or tr("ui.create_failed")); return end
  addLocal(rel, true)
  expanded[parent] = true
  if asSpace then
    currentSpace = rel
    selectedDir = rel
    expanded[rel] = true
  else
    expanded[rel] = true
    selectedDir = rel
  end
  markMutation()
  scheduleSave()
  render()
end

local function renameNote(rel, rawName)
  local name = stripSuffix(notes.sanitize(rawName))
  if name == "" then
    notifyError(tr("ui.invalid_name"))
    return
  end
  local target = noteDestination(notes.parent(rel), name .. suffix)
  if target == rel then return end
  if noctalia.fileExists(notes.path(root, target)) then
    notifyError(tr("ui.exists"))
    return
  end
  if openRel == rel then flush() end
  local ok, err = noctalia.renameFile(notes.path(root, rel), notes.path(root, target))
  if not ok then notifyError(err or tr("ui.rename_failed")); return end
  local e = byRel[rel]
  if e ~= nil then
    e.rel = target
    e.name = notes.base(target)
    e.parent = notes.parent(target)
  end
  if openRel == rel then
    openRel = target
    editorSeed += 1
  end
  if selectedDir == rel then selectedDir = target end
  rebuild()
  markMutation()
  scheduleSave()
  render()
end

local function applyDirRename(rel, target)
  local oldExpanded = {}
  for key in pairs(expanded) do
    if notes.isUnder(key, rel) then oldExpanded[key] = true end
  end
  for key in pairs(oldExpanded) do expanded[key] = nil end
  for key in pairs(oldExpanded) do
    expanded[target .. key:sub(#rel + 1)] = true
  end

  if currentSpace == rel then currentSpace = target end
  if selectedDir ~= "" and notes.isUnder(selectedDir, rel) then
    selectedDir = target .. selectedDir:sub(#rel + 1)
  end
  if openRel ~= nil and notes.isUnder(openRel, rel) then
    openRel = target .. openRel:sub(#rel + 1)
  end
  renameLocalPrefix(rel, target)
  expanded[target] = true
  markMutation()
  scheduleSave()
  render()
end

local function renameDir(rel, rawName)
  local name = notes.sanitize(rawName)
  if name == "" then
    notifyError(tr("ui.invalid_name"))
    return
  end
  local target = (notes.parent(rel) == "") and name or (notes.parent(rel) .. "/" .. name)
  if target == rel then return end
  if noctalia.fileExists(notes.path(root, target)) then
    notifyError(tr("ui.exists"))
    return
  end
  flush()
  local from = notes.path(root, rel)
  local to = notes.path(root, target)
  local ok = noctalia.renameFile(from, to)
  if ok then
    applyDirRename(rel, target)
    return
  end

  -- Some filesystems refuse rename(2) on directories through the wrapper;
  -- fall back to mv and only update the view after it succeeds.
  local started = noctalia.runAsync({ notes.expandBinary("mv"), from, to }, function(result)
    if result == nil or result.timedOut or result.exitCode ~= 0 then
      notifyError(tr("ui.rename_failed"))
      notes.requestScan()
      return
    end
    applyDirRename(rel, target)
  end)
  if not started then notifyError(tr("ui.rename_failed")) end
end

local function deleteNote(rel)
  local ok, err = noctalia.removeFile(notes.path(root, rel))
  if not ok then notifyError(err or tr("ui.delete_failed")); return end
  if openRel == rel then clearEditor() end
  removeLocalPrefix(rel)
  markMutation()
  scheduleSave()
  render()
end

local function deleteDir(rel)
  local path = notes.path(root, rel)
  local list = noctalia.listDir(path)
  if list == nil then
    notifyError(tr("ui.delete_failed"))
    return
  end
  if #list > 0 then
    notifyError(tr("ui.folder_not_empty"))
    return
  end
  local rmdir = notes.expandBinary("rmdir")
  local started = noctalia.runAsync({ rmdir, path }, function(result)
    if result == nil or result.timedOut or result.exitCode ~= 0 then
      notifyError(tr("ui.delete_failed"))
      notes.requestScan()
      return
    end
    if openRel ~= nil and notes.isUnder(openRel, rel) then clearEditor() end
    if currentSpace == rel then currentSpace = nil end
    if selectedDir == rel then selectedDir = "" end
    removeLocalPrefix(rel)
    markMutation()
    scheduleSave()
    render()
  end)
  if not started then
    notifyError(tr("ui.delete_failed"))
  end
end

local function moveNote(rel, targetParent)
  if rel == nil then return end
  local e = byRel[rel]
  if e == nil or e.dir then return end
  local parent = targetParent or ""
  if parent == LOOSE then parent = "" end
  local dest = noteDestination(parent, notes.base(rel))
  if dest == rel then return end
  if noctalia.fileExists(notes.path(root, dest)) then
    notifyError(tr("ui.exists"))
    return
  end
  flush()
  local ok, err = noctalia.renameFile(notes.path(root, rel), notes.path(root, dest))
  if not ok then notifyError(err or tr("ui.move_failed")); return end
  e.rel = dest
  e.parent = parent
  e.space = entrySpace(dest, false)
  if openRel == rel then
    openRel = dest
    editorSeed += 1
  end
  expanded[parent] = true
  local space = e.space
  currentSpace = (space == "") and LOOSE or space
  selectedDir = parent
  rebuild()
  markMutation()
  scheduleSave()
  render()
end

-- ── Prompts ─────────────────────────────────────────────────────────────────

local function openPrompt(tableValue)
  promptNonce += 1
  tableValue.nonce = promptNonce
  tableValue.value = tableValue.value or ""
  prompt = tableValue
  promptSeedKey = nil
  -- Recreate the editor input so it stops owning keyboard focus and the
  -- prompt's fresh input can take it.
  editorSeed += 1
  render()
end

local function closePrompt()
  prompt = nil
  promptSeedKey = nil
  editorSeed += 1
  render()
end

local function confirmDelete(kind, rel, label)
  openPrompt({
    kind = "confirm",
    action = kind,
    rel = rel,
    title = tr("ui.confirm_delete", { name = label }),
    hint = (kind == "note") and nil or tr("ui.folder_delete_hint"),
  })
end

local function performConfirmed()
  local p = prompt
  if p == nil then return end
  prompt = nil
  promptSeedKey = nil
  editorSeed += 1
  if p.action == "note" then
    deleteNote(p.rel)
  elseif p.action == "dir" then
    deleteDir(p.rel)
  end
end

local function submitPrompt()
  local p = prompt
  if p == nil then return end
  if p.kind == "confirm" then
    performConfirmed()
    return
  end
  local name = notes.sanitize(p.value)
  if name == "" then
    notifyError(tr("ui.invalid_name"))
    return
  end
  prompt = nil
  promptSeedKey = nil
  editorSeed += 1
  if p.kind == "new-note" then
    createNote(p.parent, name)
  elseif p.kind == "new-folder" then
    createFolder(p.parent, name, false)
  elseif p.kind == "new-space" then
    createFolder("", name, true)
  elseif p.kind == "rename-note" then
    renameNote(p.rel, name)
  elseif p.kind == "rename-dir" then
    renameDir(p.rel, name)
  end
end

-- ── Index lifecycle ─────────────────────────────────────────────────────────

local function onExternalIndex(value)
  if type(value) ~= "table" then return end
  ingest(value)
end

noctalia.state.watch(notes.INDEX_KEY, onExternalIndex)

noctalia.state.watch(notes.OPEN_KEY, function(rel)
  if type(rel) ~= "string" or rel == "" then return end
  noctalia.state.set(notes.OPEN_KEY, "")
  if isOpen then
    if byRel[rel] ~= nil then openNote(rel) else pendingOpenRel = rel end
  else
    pendingOpenRel = rel
  end
end)

-- ── Rendering: sidebar ──────────────────────────────────────────────────────

local function noteRow(e, depth)
  local selected = openRel == e.rel
  local props = {
    key = "note:" .. e.rel,
    gap = 6,
    align = "center",
    paddingV = 5,
    paddingH = 8 + depth * 12,
    radius = 6,
    onClick = function() openNote(e.rel) end,
  }
  -- Always pass fill: dropping the prop does not reliably repaint the retained
  -- row, which left the previously selected note highlighted.
  props.fill = selected and "primary/0.14" or "#00000000"
  local color = selected and "primary" or "on_surface"
  -- Only a grip is a drag source: DragSource installs a full-surface input
  -- area that swallows clicks, so wrapping the whole row would make the note
  -- impossible to open with the mouse. previewAncestor=1 drags the whole row.
  return ui.row(props, {
    ui.dragSource({
      key = "drag:" .. e.rel,
      dragType = "notes-md-note",
      payload = e.rel,
      previewAncestor = 1,
      tooltip = tr("ui.drag_hint"),
    }, {
      ui.glyph({ name = "grip-vertical", size = 13, color = "on_surface_variant" }),
    }),
    ui.glyph({ name = "markdown", size = 13, color = selected and "primary" or "on_surface_variant" }),
    ui.label({ text = notes.stem(e.name), fontSize = 12, color = color, maxLines = 1, flexGrow = 1 }),
  })
end

local function folderActions(e)
  return {
    ui.button({
      key = "dir-note:" .. e.rel,
      glyph = "file-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_note"),
      onClick = function()
        openPrompt({ kind = "new-note", parent = e.rel, title = tr("ui.new_note_in", { path = displayRel(e.rel) }), value = "Untitled" })
      end,
    }),
    ui.button({
      key = "dir-sub:" .. e.rel,
      glyph = "folder-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_folder"),
      onClick = function()
        openPrompt({ kind = "new-folder", parent = e.rel, title = tr("ui.new_folder_in", { path = displayRel(e.rel) }) })
      end,
    }),
    ui.button({
      key = "dir-ren:" .. e.rel,
      glyph = "pencil",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.rename"),
      onClick = function()
        openPrompt({ kind = "rename-dir", rel = e.rel, title = tr("ui.rename_folder"), value = e.name })
      end,
    }),
    ui.button({
      key = "dir-del:" .. e.rel,
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.delete"),
      onClick = function() confirmDelete("dir", e.rel, displayRel(e.rel)) end,
    }),
  }
end

local function folderRow(e, depth)
  local isSel = selectedDir == e.rel
  local open = expanded[e.rel] == true
  local props = {
    key = "dir:" .. e.rel,
    gap = 6,
    align = "center",
    paddingV = 4,
    paddingH = 8 + depth * 12,
    radius = 6,
    onClick = function()
      selectedDir = e.rel
      expanded[e.rel] = not open
      scheduleSave()
      render()
    end,
  }
  props.fill = isSel and "primary/0.10" or "#00000000"
  local children = {
    ui.glyph({ name = open and "chevron-down" or "chevron-right", size = 13, color = "on_surface_variant" }),
    ui.glyph({
      name = open and "folder-open" or "folder",
      size = 14,
      color = isSel and "primary" or "on_surface_variant",
    }),
    ui.label({
      text = e.name,
      fontSize = 12,
      color = isSel and "primary" or "on_surface",
      maxLines = 1,
      flexGrow = 1,
    }),
    ui.label({
      text = tostring(folderCounts[e.rel] or 0),
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  }
  if isSel then
    for _, node in ipairs(folderActions(e)) do children[#children + 1] = node end
  end
  return ui.dropZone({
    key = "drop-dir:" .. e.rel,
    accepts = { "notes-md-note" },
    value = e.rel,
    onDrop = function(payload, value) moveNote(payload, value) end,
    direction = "column",
    enabled = true,
  }, {
    ui.row(props, children),
  })
end

local function treeChildren(parentRel, depth, out)
  local dirs = dirsByParent[parentRel] or {}
  for _, e in ipairs(dirs) do
    out[#out + 1] = folderRow(e, depth)
    if expanded[e.rel] then
      treeChildren(e.rel, depth + 1, out)
    end
  end
  local ns = notesByParent[parentRel] or {}
  if #ns > 0 then
    out[#out + 1] = ui.row({ key = "unfiled:" .. parentRel, paddingH = 8 + depth * 12, paddingV = 5 }, {
      ui.glyph({ name = "corner-down-right", size = 11, color = "on_surface_variant" }),
      ui.label({ text = tr("ui.unfiled"), fontSize = 10, color = "on_surface_variant" }),
    })
    for _, e in ipairs(ns) do out[#out + 1] = noteRow(e, depth) end
  end
end

local function searchRow(e)
  local props = {
    key = "search-note:" .. e.rel,
    gap = 6,
    align = "center",
    paddingV = 5,
    paddingH = 8,
    radius = 6,
    onClick = function() openNote(e.rel) end,
  }
  props.fill = openRel == e.rel and "primary/0.14" or "#00000000"
  return ui.row(props, {
    ui.glyph({ name = "markdown", size = 13, color = "on_surface_variant" }),
    ui.column({ gap = 1, flexGrow = 1 }, {
      ui.label({ text = notes.stem(e.name), fontSize = 12, color = "on_surface", maxLines = 1 }),
      ui.label({ text = displayRel(e.parent), fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
    }),
  })
end

local function searchResults()
  local needle = query:lower()
  local out = {}
  local seen = {}
  for _, e in ipairs(entries) do
    if not e.dir then
      local stem = notes.stem(e.name)
      local hit = stem:lower():find(needle, 1, true) ~= nil
        or e.rel:lower():find(needle, 1, true) ~= nil
      if not hit and #needle >= 2 then
        hit = noctalia.fuzzyScore(query, stem) ~= nil
      end
      if hit and not seen[e.rel] then
        seen[e.rel] = true
        out[#out + 1] = e
        if #out >= MAX_SEARCH_RESULTS then break end
      end
    end
  end
  if #out == 0 then
    return { ui.label({ text = tr("ui.no_results"), fontSize = 12, color = "on_surface_variant", padding = 8 }) }
  end
  local rows = {}
  for _, e in ipairs(out) do rows[#rows + 1] = searchRow(e) end
  return rows
end

local function promptBanner()
  if prompt == nil then return nil end
  if prompt.kind == "confirm" then
    local children = {
      ui.glyph({ name = "alert-triangle", size = 16, color = "error" }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = prompt.title or "", fontSize = 12, color = "on_surface", maxLines = 2 }),
      }),
    }
    if prompt.hint ~= nil then
      children[2] = ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = prompt.title or "", fontSize = 12, color = "on_surface", maxLines = 2 }),
        ui.label({ text = prompt.hint, fontSize = 10, color = "on_surface_variant", maxLines = 2 }),
      })
    end
    children[#children + 1] = ui.button({
      key = "confirm-yes",
      text = tr("ui.delete"),
      glyph = "trash",
      variant = "destructive",
      controlSize = "sm",
      onClick = performConfirmed,
    })
    children[#children + 1] = ui.button({
      key = "confirm-no",
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      onClick = closePrompt,
    })
    return ui.row({
      key = "prompt-confirm",
      gap = 8,
      align = "center",
      padding = 8,
      radius = 8,
      fill = "error/0.12",
    }, children)
  end

  local inputKey = "prompt-input:" .. tostring(prompt.nonce)
  local props = {
    key = inputKey,
    placeholder = tr("ui.name_placeholder"),
    fontSize = 12,
    flexGrow = 1,
    onChange = function(value) prompt.value = value or "" end,
    onSubmit = submitPrompt,
  }
  if promptSeedKey ~= inputKey then
    props.value = prompt.value
    props.focus = true
    promptSeedKey = inputKey
  end
  return ui.column({
    key = "prompt-entry",
    gap = 6,
    padding = 8,
    radius = 8,
    fill = "surface_variant/0.18",
  }, {
    ui.label({ text = prompt.title or "", fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input(props),
      ui.button({
        key = "prompt-ok",
        glyph = "check",
        variant = "primary",
        controlSize = "sm",
        tooltip = tr("ui.confirm"),
        onClick = submitPrompt,
      }),
      ui.button({
        key = "prompt-cancel",
        glyph = "close",
        variant = "ghost",
        controlSize = "sm",
        tooltip = tr("ui.cancel"),
        onClick = closePrompt,
      }),
    }),
  })
end

local function spaceChip(name, label, glyph)
  local isSel = currentSpace == name
  local accent = (name == LOOSE) and "#b4befe" or notes.spaceColor(name)
  local fill = isSel and (accent .. "33") or "surface_variant/0.20"
  local chip = ui.column({
    key = "space:" .. name,
    width = 44,
    height = 44,
    radius = 10,
    align = "center",
    justify = "center",
    fill = fill,
    border = isSel and accent or "outline/0.4",
    borderWidth = 1,
    onClick = function()
      currentSpace = name
      selectedDir = (name == LOOSE) and "" or name
      scheduleSave()
      render()
    end,
  }, {
    glyph ~= nil
      and ui.glyph({ name = glyph, size = 16, color = isSel and accent or "on_surface_variant" })
      or ui.label({ text = label, fontSize = 14, fontWeight = "bold", color = isSel and accent or "on_surface" }),
  })
  return ui.dropZone({
    key = "drop-space:" .. name,
    accepts = { "notes-md-note" },
    value = name,
    onDrop = function(payload, value) moveNote(payload, value == LOOSE and "" or value) end,
    direction = "column",
    enabled = true,
  }, { chip })
end

local function spacesRail()
  local children = {}
  for _, name in ipairs(spaces) do
    children[#children + 1] = spaceChip(name, name:sub(1, 1):upper())
  end
  if rootNoteCount > 0 then
    children[#children + 1] = ui.separator({ key = "space-sep", color = "outline", opacity = 0.25 })
    children[#children + 1] = spaceChip(LOOSE, nil, "file-text")
  end
  local rail = ui.scroll({ key = "spaces-scroll", gap = 8, width = 54, flexGrow = 1 }, children)
  return ui.column({ width = 54, gap = 8, align = "center" }, {
    rail,
    ui.button({
      key = "space-new",
      glyph = "plus",
      variant = "outline",
      controlSize = "sm",
      tooltip = tr("ui.new_space"),
      onClick = function()
        openPrompt({ kind = "new-space", parent = "", title = tr("ui.new_space") })
      end,
    }),
  })
end

local function spaceHeader()
  if currentSpace == nil then
    return ui.label({ text = tr("ui.no_spaces"), fontSize = 12, color = "on_surface_variant" })
  end
  local loose = currentSpace == LOOSE
  local name = loose and tr("ui.loose") or currentSpace
  local children = {
    ui.glyph({ name = loose and "file-text" or "folder", size = 14, color = "primary" }),
    ui.label({ text = name, fontSize = 13, fontWeight = "bold", color = "on_surface", maxLines = 1, flexGrow = 1 }),
  }
  if not loose then
    children[#children + 1] = ui.button({
      key = "space-note",
      glyph = "file-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_note"),
      onClick = function()
        openPrompt({ kind = "new-note", parent = currentSpace, title = tr("ui.new_note_in", { path = displayRel(currentSpace) }), value = "Untitled" })
      end,
    })
    children[#children + 1] = ui.button({
      key = "space-folder",
      glyph = "folder-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_folder"),
      onClick = function()
        openPrompt({ kind = "new-folder", parent = currentSpace, title = tr("ui.new_folder_in", { path = displayRel(currentSpace) }) })
      end,
    })
    children[#children + 1] = ui.button({
      key = "space-rename",
      glyph = "pencil",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.rename"),
      onClick = function()
        openPrompt({ kind = "rename-dir", rel = currentSpace, title = tr("ui.rename_space"), value = currentSpace })
      end,
    })
    children[#children + 1] = ui.button({
      key = "space-delete",
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.delete"),
      onClick = function() confirmDelete("dir", currentSpace, currentSpace) end,
    })
  end
  return ui.row({ key = "space-header", gap = 6, align = "center" }, children)
end

local function sidebar()
  local children = {}

  local promptNode = promptBanner()
  if promptNode ~= nil then children[#children + 1] = promptNode end

  local searchProps = {
    key = "notes-search",
    placeholder = tr("ui.search_placeholder"),
    fontSize = 12,
    flexGrow = 1,
    onChange = function(value)
      query = value or ""
      searchDue = noctalia.nowMs() + SEARCH_DEBOUNCE_MS
      panel.setNeedsFrameTick(true)
    end,
  }
  if not querySeeded then
    searchProps.value = ""
    querySeeded = true
  end
  local searchChildren = { ui.input(searchProps) }
  if query ~= "" then
    searchChildren[#searchChildren + 1] = ui.button({
      key = "search-clear",
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.clear_search"),
      onClick = function()
        query = ""
        querySeeded = false
        render()
      end,
    })
  end
  children[#children + 1] = ui.row({ key = "search-row", gap = 4, align = "center" }, searchChildren)

  if query == "" then
    children[#children + 1] = spaceHeader()
    local rows = {}
    if indexError == "root_missing" then
      rows[#rows + 1] = ui.column({ key = "root-missing", gap = 6, padding = 8 }, {
        ui.label({ text = tr("ui.root_missing", { path = root }), fontSize = 11, color = "error", maxLines = 3 }),
        ui.button({
          key = "root-create",
          text = tr("ui.create_folder"),
          glyph = "folder-plus",
          variant = "primary",
          controlSize = "sm",
          onClick = function()
            local ok, err = noctalia.mkdirAll(root)
            if not ok then notifyError(err or "") else notes.requestScan() end
          end,
        }),
      })
    elseif currentSpace == nil then
      rows[#rows + 1] = ui.label({ text = tr("ui.empty_spaces"), fontSize = 12, color = "on_surface_variant", padding = 8 })
    elseif currentSpace == LOOSE then
      local list = notesByParent[""] or {}
      if #list == 0 then
        rows[#rows + 1] = ui.label({ text = tr("ui.empty_tree"), fontSize = 12, color = "on_surface_variant", padding = 8 })
      end
      for _, e in ipairs(list) do rows[#rows + 1] = noteRow(e, 0) end
    else
      treeChildren(currentSpace, 0, rows)
      if #rows == 0 then
        rows[#rows + 1] = ui.label({ text = tr("ui.empty_tree"), fontSize = 12, color = "on_surface_variant", padding = 8 })
      end
    end
    children[#children + 1] = ui.scroll({ key = "tree-scroll", flexGrow = 1, gap = 2 }, rows)
  else
    children[#children + 1] = ui.scroll({ key = "search-scroll", flexGrow = 1, gap = 2 }, searchResults())
  end

  local footer = {}
  local count = (currentSpace == LOOSE and rootNoteCount) or (currentSpace and spaceCounts[currentSpace]) or 0
  footer[#footer + 1] = ui.label({
    key = "tree-count",
    text = tr("ui.note_count", { count = tostring(count) }),
    fontSize = 10,
    color = "on_surface_variant",
  })
  footer[#footer + 1] = ui.spacer({ flexGrow = 1 })
  if truncated then
    footer[#footer + 1] = ui.label({ text = tr("ui.truncated"), fontSize = 10, color = "#f9e2af" })
  end
  footer[#footer + 1] = ui.button({
    key = "tree-refresh",
    glyph = "refresh",
    variant = "ghost",
    controlSize = "sm",
    tooltip = tr("ui.refresh"),
    onClick = function() notes.requestScan() end,
  })
  children[#children + 1] = ui.row({ key = "tree-footer", gap = 6, align = "center" }, footer)

  return ui.column({ width = SIDEBAR_WIDTH, gap = 8 }, children)
end

-- ── Rendering: editor ───────────────────────────────────────────────────────

local function modeButton(mode, glyph, tooltip)
  return ui.button({
    key = "mode-" .. mode,
    glyph = glyph,
    variant = previewMode == mode and "primary" or "ghost",
    controlSize = "sm",
    selected = previewMode == mode,
    tooltip = tooltip,
    onClick = function()
      previewMode = mode
      scheduleSave()
      render()
    end,
  })
end

local function editorHeader()
  local children = {
    ui.label({
      text = openRel ~= nil and displayNotePath(openRel) or tr("ui.title"),
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 1,
      flexGrow = 1,
    }),
  }
  if openRel ~= nil then
    children[#children + 1] = modeButton("split", "columns", tr("ui.preview_split"))
    children[#children + 1] = modeButton("edit", "pencil", tr("ui.preview_edit"))
    children[#children + 1] = modeButton("preview", "eye", tr("ui.preview_only"))
    children[#children + 1] = ui.button({
      key = "note-rename",
      glyph = "pencil",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.rename"),
      onClick = function()
        openPrompt({
          kind = "rename-note",
          rel = openRel,
          title = tr("ui.rename_note"),
          value = notes.stem(notes.base(openRel)),
        })
      end,
    })
    children[#children + 1] = ui.button({
      key = "note-move",
      glyph = "arrows-move",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.move"),
      onClick = function()
        movePicker = not movePicker
        render()
      end,
    })
    children[#children + 1] = ui.button({
      key = "note-delete",
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.delete"),
      onClick = function()
        confirmDelete("note", openRel, notes.stem(notes.base(openRel)))
      end,
    })
  end
  return ui.row({ key = "editor-header", gap = 4, align = "center" }, children)
end

local function editorInput()
  local key = "editor:" .. tostring(openRel) .. ":" .. tostring(editorSeed)
  local props = {
    key = key,
    multiline = true,
    fontSize = 12,
    flexGrow = 1,
    placeholder = tr("ui.editor_placeholder"),
    onChange = function(value)
      buffer = value or ""
      dirty = true
      duePreview = noctalia.nowMs() + PREVIEW_DEBOUNCE_MS
      dueSave = noctalia.nowMs() + AUTOSAVE_DEBOUNCE_MS
      panel.setNeedsFrameTick(true)
    end,
    onSubmit = function()
      flush()
      render()
    end,
  }
  if lastEditorKey ~= key then
    props.value = buffer
    if prompt == nil and not movePicker then props.focus = true end
    lastEditorKey = key
  end
  return ui.input(props)
end

local function previewColumn(width)
  local children = {}
  if buffer == "" then
    children[#children + 1] = ui.row({ key = "preview-empty", gap = 8, align = "center", padding = 10 }, {
      ui.glyph({ name = "markdown", size = 15, color = "on_surface_variant" }),
      ui.label({ text = tr("ui.preview_empty"), fontSize = 12, color = "on_surface_variant" }),
    })
  else
    local text = buffer
    if #buffer > MAX_PREVIEW_BYTES then
      text = buffer:sub(1, MAX_PREVIEW_BYTES) .. "\n\n---\n\n" .. tr("ui.preview_truncated")
    end
    children[#children + 1] = ui.markdown({ key = "preview", text = text, width = width })
  end
  return ui.scroll({ key = "preview-scroll", flexGrow = 1, gap = 0 }, children)
end

local function editorBody()
  if openRel == nil then
    return ui.column({ key = "editor-empty", flexGrow = 1, gap = 10, align = "center", justify = "center" }, {
      ui.glyph({ name = "notes", size = 30, color = "primary" }),
      ui.label({ text = tr("ui.select_note"), fontSize = 13, color = "on_surface_variant" }),
      ui.button({
        key = "empty-new-note",
        text = tr("ui.new_note"),
        glyph = "file-plus",
        variant = "primary",
        onClick = function()
          local parent = selectedDir ~= "" and selectedDir or ((currentSpace == LOOSE) and "" or currentSpace or "")
          openPrompt({ kind = "new-note", parent = parent, title = tr("ui.new_note_in", { path = displayRel(parent) }), value = "Untitled" })
        end,
      }),
    })
  end

  if movePicker then
    local targets = {}
    if rootNoteCount > 0 then
      targets[#targets + 1] = { rel = "", label = tr("ui.loose") }
    end
    local allDirs = {}
    for _, e in ipairs(entries) do
      if e.dir then allDirs[#allDirs + 1] = e end
    end
    table.sort(allDirs, function(a, b) return a.rel:lower() < b.rel:lower() end)
    for _, e in ipairs(allDirs) do
      targets[#targets + 1] = { rel = e.rel, label = displayRel(e.rel) }
    end
    local rows = {
      ui.row({ key = "move-head", gap = 6, align = "center" }, {
        ui.glyph({ name = "arrows-move", size = 15, color = "primary" }),
        ui.label({ text = tr("ui.move_to"), fontSize = 13, fontWeight = "bold", flexGrow = 1 }),
        ui.button({
          key = "move-cancel",
          glyph = "close",
          variant = "ghost",
          controlSize = "sm",
          tooltip = tr("ui.cancel"),
          onClick = function()
            movePicker = false
            render()
          end,
        }),
      }),
    }
    for index, target in ipairs(targets) do
      local targetRel = target.rel
      rows[#rows + 1] = ui.row({
        key = "move-target:" .. index .. ":" .. targetRel,
        gap = 8,
        align = "center",
        padding = 8,
        radius = 6,
        onClick = function()
          movePicker = false
          moveNote(openRel, targetRel)
        end,
      }, {
        ui.glyph({ name = "folder", size = 13, color = "on_surface_variant" }),
        ui.label({ text = target.label, fontSize = 12, color = "on_surface", maxLines = 1, flexGrow = 1 }),
        ui.glyph({ name = "corner-down-left", size = 12, color = "on_surface_variant" }),
      })
    end
    return ui.scroll({ key = "move-scroll", flexGrow = 1, gap = 2 }, rows)
  end

  if previewMode == "edit" then
    return editorInput()
  elseif previewMode == "preview" then
    return previewColumn(FULL_PREVIEW_WIDTH)
  end
  return ui.row({ key = "split-body", gap = 10, flexGrow = 1 }, {
    ui.column({ key = "editor-col", flexGrow = 1 }, { editorInput() }),
    ui.column({ key = "preview-col", flexGrow = 1 }, { previewColumn(SPLIT_PREVIEW_WIDTH) }),
  })
end

local function editorStatus()
  if openRel == nil then return nil end
  local state = dirty and tr("ui.unsaved") or tr("ui.saved")
  local words = select(2, buffer:gsub("%S+", ""))
  local chars = utf8.len(buffer) or #buffer
  return ui.row({ key = "editor-status", gap = 6, align = "center" }, {
    ui.glyph({ name = dirty and "circle-dot" or "check", size = 12, color = dirty and "#f9e2af" or "#a6e3a1" }),
    ui.label({
      text = state .. "  ·  " .. tr("ui.counts", { words = tostring(words), chars = tostring(chars) }),
      fontSize = 10,
      color = "on_surface_variant",
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = root, fontSize = 10, color = "on_surface_variant", maxLines = 1, opacity = 0.7 }),
  })
end

local function editorPane()
  local children = { editorHeader(), editorBody() }
  local status = editorStatus()
  if status ~= nil then children[#children + 1] = status end
  return ui.column({ flexGrow = 1, gap = 8 }, children)
end

-- ── Render ──────────────────────────────────────────────────────────────────

render = function()
  if not isOpen then return end
  local header = {
    ui.glyph({ name = "notes", size = 16, color = "primary" }),
    ui.label({ text = tr("ui.title"), fontSize = 16, fontWeight = "bold", color = "on_surface" }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      key = "head-new-note",
      glyph = "file-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_note"),
      onClick = function()
        local parent = selectedDir ~= "" and selectedDir or ((currentSpace == LOOSE) and "" or currentSpace or "")
        openPrompt({ kind = "new-note", parent = parent, title = tr("ui.new_note_in", { path = displayRel(parent) }), value = "Untitled" })
      end,
    }),
    ui.button({
      key = "head-new-folder",
      glyph = "folder-plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.new_folder"),
      onClick = function()
        if currentSpace == LOOSE then
          openPrompt({ kind = "new-space", parent = "", title = tr("ui.new_space") })
        else
          local parent = selectedDir ~= "" and selectedDir or (currentSpace or "")
          openPrompt({ kind = "new-folder", parent = parent, title = tr("ui.new_folder_in", { path = displayRel(parent) }) })
        end
      end,
    }),
    ui.button({
      key = "head-refresh",
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.refresh"),
      onClick = function() notes.requestScan() end,
    }),
    ui.button({
      key = "head-close",
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.close"),
      onClick = function() panel.close() end,
    }),
  }

  panel.render(ui.column({ flexGrow = 1, gap = 10, padding = 12 }, {
    ui.row({ key = "panel-header", gap = 8, align = "center" }, header),
    ui.separator({ color = "outline", opacity = 0.2 }),
    ui.row({ key = "panel-body", gap = 12, flexGrow = 1 }, {
      spacesRail(),
      sidebar(),
      ui.column({ key = "editor-divider", width = 1, fill = "outline/0.2" }, {}),
      editorPane(),
    }),
  }))
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

saveUiState = function()
  dueState = 0
  notes.writeUiState({
    lastSpace = currentSpace,
    lastNote = openRel,
    expanded = expanded,
    previewMode = previewMode,
    sortMode = sortMode,
  })
end

function onOpen(_context)
  isOpen = true
  noctalia.state.set(notes.PANEL_OPEN_KEY, true)
  root = notes.root()
  suffix = notes.suffix()

  local saved = notes.readUiState()
  expanded = type(saved.expanded) == "table" and saved.expanded or {}
  previewMode = cfgPreviewMode()
  if saved.previewMode == "split" or saved.previewMode == "edit" or saved.previewMode == "preview" then
    previewMode = saved.previewMode
  end
  sortMode = cfgSortMode()

  currentSpace = nil
  if type(saved.lastSpace) == "string" and saved.lastSpace ~= "" then currentSpace = saved.lastSpace end
  selectedDir = ""
  if currentSpace ~= nil and currentSpace ~= LOOSE then selectedDir = currentSpace end

  local snapshot = noctalia.state.get(notes.INDEX_KEY)
  if type(snapshot) == "table" and snapshot.root == root then
    entries = notes.cloneEntries(snapshot.entries)
    indexError = snapshot.error
    truncated = snapshot.truncated == true
  else
    entries = {}
    indexError = nil
    truncated = false
    notes.requestScan()
  end
  rebuild()

  query = ""
  querySeeded = false
  movePicker = false
  prompt = nil
  promptSeedKey = nil
  lastEditorKey = nil
  restoreRel = nil
  duePreview = 0
  dueSave = 0

  local lastNote = saved.lastNote
  if type(lastNote) == "string" and lastNote ~= "" and byRel[lastNote] ~= nil then
    openRel = lastNote
    buffer = noctalia.readFile(notes.path(root, lastNote)) or ""
    loadedContent = buffer
    dirty = false
    editorSeed += 1
    expandAncestors(lastNote)
    local space = entrySpace(lastNote, false)
    currentSpace = (space == "") and LOOSE or space
    selectedDir = notes.parent(lastNote)
    if selectedDir == "" and currentSpace ~= LOOSE then selectedDir = currentSpace end
  else
    openRel = nil
    buffer = ""
    loadedContent = ""
    dirty = false
    if type(lastNote) == "string" and lastNote ~= "" then
      -- The index may still be loading; open it once the scan lands.
      if noctalia.fileExists(notes.path(root, lastNote)) then
        restoreRel = lastNote
        notes.requestScan()
      end
    end
  end

  if pendingOpenRel ~= nil then
    local pending = pendingOpenRel
    pendingOpenRel = nil
    if byRel[pending] ~= nil then
      openRel = nil
      openNote(pending)
    end
  end

  local target = noctalia.state.get(notes.OPEN_KEY)
  if type(target) == "string" and target ~= "" then
    noctalia.state.set(notes.OPEN_KEY, "")
    if byRel[target] ~= nil then
      openRel = nil
      openNote(target)
    else
      pendingOpenRel = target
    end
  end

  if noctalia.state.get(notes.NEW_KEY) == true then
    noctalia.state.set(notes.NEW_KEY, false)
    local parent = selectedDir ~= "" and selectedDir or ((currentSpace == LOOSE) and "" or currentSpace or "")
    openPrompt({ kind = "new-note", parent = parent, title = tr("ui.new_note_in", { path = displayRel(parent) }), value = "Untitled" })
  end

  panel.setNeedsFrameTick(true)
  render()
end

function onClose()
  flush()
  saveUiState()
  isOpen = false
  pendingOpenRel = nil
  noctalia.state.set(notes.PANEL_OPEN_KEY, false)
end

function onExit(signal, reason)
  if isOpen or dirty then
    flush()
    saveUiState()
  end
  isOpen = false
end

function onFrameTick(_deltaMs)
  if not isOpen then return end
  local now = noctalia.nowMs()
  local needRender = false
  if duePreview > 0 and now >= duePreview then
    duePreview = 0
    if previewMode ~= "edit" then needRender = true end
  end
  if dueSave > 0 and now >= dueSave then
    dueSave = 0
    flush()
    needRender = true
  end
  if searchDue > 0 and now >= searchDue then
    searchDue = 0
    needRender = true
  end
  if dueState > 0 and now >= dueState then
    saveUiState()
  end
  if needRender then render() end
end

function onIpc(event, payload)
  if event == "open" and type(payload) == "string" then
    openNote(payload)
  elseif event == "space" and type(payload) == "string" then
    if spaceSet[payload] then
      currentSpace = payload
      selectedDir = payload
      render()
    elseif payload == "loose" then
      currentSpace = LOOSE
      selectedDir = ""
      render()
    end
  elseif event == "new" then
    local parent = selectedDir ~= "" and selectedDir or ((currentSpace == LOOSE) and "" or currentSpace or "")
    openPrompt({ kind = "new-note", parent = parent, title = tr("ui.new_note_in", { path = displayRel(parent) }), value = "Untitled" })
  elseif event == "refresh" then
    notes.requestScan()
    render()
  elseif event == "preview" and type(payload) == "string" then
    if payload == "split" or payload == "edit" or payload == "preview" then
      previewMode = payload
      render()
    end
  elseif event == "state" then
    noctalia.notify(tr("ui.title"), tostring(#entries) .. " entries · index " .. tostring(indexError or "ok"))
  elseif event == "create" and type(payload) == "string" then
    local parent, name = payload:match("^(.-)|(.+)$")
    if name ~= nil then createNote(parent, name) end
  elseif event == "mkdir" and type(payload) == "string" then
    local parent, name = payload:match("^(.-)|(.+)$")
    if name ~= nil then createFolder(parent, name, parent == "") end
  elseif event == "rename" and type(payload) == "string" then
    local rel, name = payload:match("^(.-)|(.+)$")
    if name ~= nil and byRel[rel] ~= nil then
      if byRel[rel].dir then renameDir(rel, name) else renameNote(rel, name) end
    end
  elseif event == "move" and type(payload) == "string" then
    local rel, parent = payload:match("^(.-)|(.*)$")
    if rel ~= nil then moveNote(rel, parent) end
  elseif event == "delete" and type(payload) == "string" then
    if byRel[payload] ~= nil then
      if byRel[payload].dir then deleteDir(payload) else deleteNote(payload) end
    end
  end
end

render()
