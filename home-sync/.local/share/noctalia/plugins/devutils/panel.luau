--!nonstrict
-- Dev Utils panel: four tools behind tabs — collapsible JSON tree, SQL
-- formatter (pg_format), markdown scratchpad with live preview, and PHP dump
-- → JSON. The /dev launcher preselects a tab via the `openTool` state key.

local treeLib = require("./lib/json-tree.luau")
local phpLib = require("./lib/php-dump.luau")
local sqlLib = require("./lib/sql.luau")

local TOOLS = {
  { id = "json",     titleKey = "tool.json.title",     glyph = "brackets" },
  { id = "sql",      titleKey = "tool.sql.title",      glyph = "database" },
  { id = "markdown", titleKey = "tool.markdown.title", glyph = "markdown" },
  { id = "php",      titleKey = "tool.php.title",      glyph = "brand-php" },
}

local st = {
  json = { input = "", value = nil, error = nil, collapsed = {}, nonce = 0, viewDepth = nil },
  sql  = { input = "", output = nil, err = nil, busy = false, nonce = 0 },
  md   = { text = "", clearArmed = false, nonce = 0 },
  php  = { input = "", value = nil, fmt = nil, err = nil, collapsed = {}, nonce = 0, viewDepth = nil },
}

local activeTool = "json"
local PREVIEW_WIDTH = 430

-- Typing/pasting must NOT re-render the panel synchronously (decode + tree
-- build + host diff of hundreds of controls = jank on every keystroke).
-- Edits only mark a tool dirty; onFrameTick flushes the work ~250ms after the
-- last change. Ticks run while the panel is open (enabled in onOpen).
local DEBOUNCE_MS = 250
local dueAt = { json = 0, php = 0, md = 0 }
local lastInputKey = nil -- input seeding: pass `value` only on fresh keys

local render, saveScratch, jsonParse, phpParse -- forward declarations

local function schedule(tool)
  dueAt[tool] = noctalia.nowMs() + DEBOUNCE_MS
  panel.setNeedsFrameTick(true)
end

local function flushDue()
  local now = noctalia.nowMs()
  local needRender = false
  for tool, at in pairs(dueAt) do
    if at > 0 and now >= at then
      dueAt[tool] = 0
      if tool == "json" then
        jsonParse()
      elseif tool == "php" then
        phpParse()
      elseif tool == "md" then
        saveScratch()
      end
      if tool == activeTool then needRender = true end
    end
  end
  if needRender then render() end
end

function onFrameTick(_deltaMs)
  flushDue()
end

local function schedule(tool)
  dueAt[tool] = noctalia.nowMs() + DEBOUNCE_MS
  panel.setNeedsFrameTick(true)
end

local function flushDue()
  local now = noctalia.nowMs()
  local needRender = false
  for tool, at in pairs(dueAt) do
    if at > 0 and now >= at then
      dueAt[tool] = 0
      if tool == "json" then
        jsonParse()
      elseif tool == "php" then
        phpParse()
      elseif tool == "md" then
        saveScratch()
      end
      if tool == activeTool then needRender = true end
    end
  end
  if needRender then render() end
end

function onFrameTick(_deltaMs)
  flushDue()
end

local function trim(s)
  return (s == nil or s == "") and "" or (s:match("^%s*(.-)%s*$"))
end

local function makeToggle(_collapsed)
  -- The tree renderer mutates the collapsed set itself; just re-render.
  return function() render() end
end

-- Default progressive-disclosure depth (0 = expand everything).
local function defaultDepth()
  local v = tonumber(noctalia.getConfig("tree_collapse_depth"))
  if v == nil or v < 0 then return 2 end
  return v
end

local function currentDepth(s)
  return s.viewDepth or defaultDepth()
end

-- Depth buttons: collapse-all / expand to level / expand-all.
local function depthControls(s)
  local cur = currentDepth(s)
  local function setDepth(d)
    s.viewDepth = d
    s.collapsed = {}
    render()
  end
  local nodes = {
    ui.button({
      key = "d-all-",
      text = "−",
      variant = "outline",
      controlSize = "sm",
      tooltip = noctalia.tr("ui.depth_none"),
      onClick = function() setDepth(1) end,
    }),
  }
  for d = 1, 3 do
    nodes[#nodes + 1] = ui.button({
      key = "d-" .. d,
      text = tostring(d),
      variant = "outline",
      controlSize = "sm",
      selected = cur == d,
      tooltip = noctalia.tr("ui.depth_level", { n = d }),
      onClick = function() setDepth(d) end,
    })
  end
  nodes[#nodes + 1] = ui.button({
    key = "d-all+",
    text = "+",
    variant = "outline",
    controlSize = "sm",
    tooltip = noctalia.tr("ui.depth_all"),
    onClick = function() setDepth(99) end,
  })
  return ui.row({ gap = 4, align = "center" }, nodes)
end

-- ── Markdown scratch persistence ─────────────────────────────────────────────

local dataDir = noctalia.pluginDataDir()
local mdPath = (dataDir ~= nil) and (dataDir .. "/markdown-scratch.md") or nil

do
  local raw = mdPath and noctalia.readFile(mdPath) or nil
  if raw then st.md.text = raw end
end

saveScratch = function()
  if mdPath == nil then return end
  if #st.md.text > 512 * 1024 then return end
  noctalia.writeFile(mdPath, st.md.text)
end

-- ── Parsing ──────────────────────────────────────────────────────────────────

jsonParse = function()
  local s = st.json
  -- Fresh parse (new content) resets progressive disclosure to the default.
  s.viewDepth = nil
  s.collapsed = {}
  if trim(s.input) == "" then
    s.value, s.error = nil, nil
    return
  end
  local ok, value = treeLib.decode(s.input)
  if ok then
    s.value, s.error = value, nil
  else
    s.value, s.error = nil, value
  end
end

phpParse = function()
  local s = st.php
  s.viewDepth = nil
  s.collapsed = {}
  if trim(s.input) == "" then
    s.value, s.fmt, s.err = nil, nil, nil
    return
  end
  local value, fmtOrErr = phpLib.parse(s.input)
  if value == nil then
    s.value, s.fmt, s.err = nil, nil, fmtOrErr
  else
    s.value, s.fmt, s.err = value, fmtOrErr, nil
  end
end

-- ── SQL ──────────────────────────────────────────────────────────────────────

local function sqlFormat()
  local s = st.sql
  if s.busy or trim(s.input) == "" then return end
  s.busy = true
  s.err = nil
  render()
  sqlLib.format(s.input, function(ok, out)
    s.busy = false
    if ok then
      s.output = out
      s.err = nil
    else
      s.err = out
    end
    render()
  end)
end

-- ── Tool bodies ──────────────────────────────────────────────────────────────

local function statusLabel(okText, ok)
  return ui.label({
    text = okText,
    fontSize = 11,
    color = ok and "success" or "error",
    maxLines = 1,
  })
end

local function hintRow(glyphName, text)
  return ui.row({ gap = 8, align = "center", paddingH = 10, paddingV = 12 }, {
    ui.glyph({ name = glyphName, size = 15, color = "on_surface_variant" }),
    ui.label({ text = text, fontSize = 12, color = "on_surface_variant", maxLines = 3 }),
  })
end

local function errorRow(text)
  return ui.row({ gap = 6, align = "center", paddingH = 10, paddingV = 8, radius = 6, fill = "error/0.12" }, {
    ui.glyph({ name = "alert-circle", size = 13, color = "error" }),
    ui.label({ text = text, fontSize = 11, color = "error", maxLines = 4, flexGrow = 1 }),
  })
end

-- Shared input-side toolbar: paste + tool-specific buttons + status.
local function toolbarRow(defs)
  local nodes = {}
  for _, d in ipairs(defs) do
    nodes[#nodes + 1] = ui.button({
      key = d.key,
      text = d.text,
      glyph = d.glyph,
      variant = d.variant or "outline",
      controlSize = "sm",
      enabled = d.enabled ~= false,
      onClick = d.onClick,
    })
  end
  nodes[#nodes + 1] = ui.spacer({ flexGrow = 1 })
  if defs.status ~= nil then nodes[#nodes + 1] = defs.status end
  return ui.row({ gap = 6, align = "center" }, nodes)
end

-- ui.input is uncontrolled: `value` only seeds at creation. Repassing the
-- field's current text on later renders makes the host rewrite the native
-- text control (selection/typing jank), so a value is passed only when the
-- key is fresh; lastInputKey resets in onOpen (native controls may not
-- survive a panel close).
local function inputPane(key, value, placeholder, onChange)
  local props = {
    key = key,
    multiline = true,
    fontSize = 12,
    flexGrow = 1,
    placeholder = placeholder,
    onChange = onChange,
  }
  if key ~= lastInputKey then
    props.value = value
    lastInputKey = key
  end
  return ui.input(props)
end

local function jsonBody()
  local s = st.json
  local empty = trim(s.input) == ""

  local status
  if empty then
    status = nil
  elseif s.error ~= nil then
    status = statusLabel(noctalia.tr("ui.invalid_json"), false)
  else
    status = statusLabel(noctalia.tr("ui.valid_json"), true)
  end

  local bar = toolbarRow({
    {
      key = "json-paste",
      text = noctalia.tr("ui.paste"),
      glyph = "clipboard",
      onClick = function()
        local clip = noctalia.clipboardText()
        if clip == nil or clip == "" then return end
        s.input = clip
        s.nonce = s.nonce + 1
        jsonParse()
        render()
      end,
    },
    {
      key = "json-copy",
      text = noctalia.tr("ui.copy"),
      glyph = "copy",
      enabled = not empty and s.error == nil,
      onClick = function()
        local pretty, err = treeLib.pretty(s.input)
        if pretty == nil then
          noctalia.notifyError("Dev Utils", err)
          return
        end
        noctalia.copyToClipboard(pretty, "text/plain")
        noctalia.notify("Dev Utils", "Pretty JSON copied")
      end,
    },
    status = status,
  })
  local depthBar = depthControls(s)

  local right
  if empty then
    right = hintRow("info-circle", noctalia.tr("ui.empty_input"))
  elseif s.error ~= nil then
    right = errorRow(s.error)
  else
    local rows, truncated = treeLib.render(s.value, s.collapsed, makeToggle(s.collapsed), {
      defaultCollapseDepth = currentDepth(s),
    })
    local kids = {}
    if truncated then
      kids[#kids + 1] = hintRow("alert-triangle", noctalia.tr("ui.truncated_tree", { max = treeLib.MAX_NODES }))
    end
    for _, r in ipairs(rows) do kids[#kids + 1] = r end
    right = ui.scroll({ gap = 0, flexGrow = 1 }, kids)
  end

  return {
    bar,
    ui.row({ gap = 10, flexGrow = 1 }, {
      ui.column({ gap = 6, flexGrow = 1 }, {
        depthBar,
        inputPane("json-input-" .. s.nonce, s.input, '{"example": [1, 2, 3]}', function(v)
          s.input = v or ""
          schedule("json")
        end),
      }),
      ui.column({ gap = 6, flexGrow = 1 }, { right }),
    }),
  }
end

local function sqlBody()
  local s = st.sql
  local status
  if s.busy then
    status = statusLabel(noctalia.tr("ui.busy"), true)
  elseif s.err ~= nil then
    status = statusLabel(noctalia.tr("ui.sql_failed"), false)
  end

  local bar = toolbarRow({
    {
      key = "sql-format",
      text = noctalia.tr("ui.format"),
      glyph = "wand",
      variant = "primary",
      onClick = sqlFormat,
    },
    {
      key = "sql-copy",
      text = noctalia.tr("ui.copy"),
      glyph = "copy",
      enabled = s.output ~= nil and s.output ~= "",
      onClick = function()
        noctalia.copyToClipboard(s.output, "text/plain")
        noctalia.notify("Dev Utils", "Formatted SQL copied")
      end,
    },
    status = status,
  })

  local right
  if s.err ~= nil then
    right = errorRow(s.err)
  elseif s.output == nil or s.output == "" then
    right = hintRow("info-circle", noctalia.tr("ui.empty_output"))
  else
    local lines = {}
    for line in s.output:gmatch("([^\n]*)\n?") do
      lines[#lines + 1] = ui.label({
        text = (line == "" and " " or line),
        fontSize = 12,
        color = "on_surface",
        maxLines = 1,
      })
    end
    right = ui.scroll({ gap = 0, flexGrow = 1 }, lines)
  end

  return {
    bar,
    ui.row({ gap = 10, flexGrow = 1 }, {
      ui.column({ gap = 6, flexGrow = 1 }, {
        inputPane("sql-input-" .. s.nonce, s.input, "SELECT * FROM users WHERE id = 1", function(v)
          s.input = v or ""
        end),
      }),
      ui.column({ gap = 6, flexGrow = 1 }, { right }),
    }),
  }
end

local function markdownBody()
  local s = st.md
  local bar = toolbarRow({
    {
      key = "md-copy",
      text = noctalia.tr("ui.copy"),
      glyph = "copy",
      enabled = trim(s.text) ~= "",
      onClick = function()
        noctalia.copyToClipboard(s.text, "text/plain")
        noctalia.notify("Dev Utils", "Markdown copied")
      end,
    },
    {
      key = "md-clear",
      text = s.clearArmed and noctalia.tr("ui.confirm_clear") or noctalia.tr("ui.clear"),
      glyph = s.clearArmed and "alert-triangle" or "eraser",
      variant = s.clearArmed and "destructive" or "outline",
      enabled = trim(s.text) ~= "",
      onClick = function()
        if not s.clearArmed then
          s.clearArmed = true
          render()
          return
        end
        s.clearArmed = false
        s.text = ""
        s.nonce = s.nonce + 1
        saveScratch()
        render()
      end,
    },
    status = ui.label({
      text = noctalia.tr("ui.scratch_saved") .. " · " .. #s.text .. " B",
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  })

  local preview
  if trim(s.text) == "" then
    preview = hintRow("markdown", noctalia.tr("ui.empty_input"))
  else
    preview = ui.scroll({ gap = 0, flexGrow = 1 }, {
      ui.markdown({ text = s.text, width = PREVIEW_WIDTH }),
    })
  end

  return {
    bar,
    ui.row({ gap = 10, flexGrow = 1 }, {
      ui.column({ gap = 6, flexGrow = 1 }, {
        inputPane("md-input-" .. s.nonce, s.text, "# Hello", function(v)
          s.text = v or ""
          schedule("md")
        end),
      }),
      ui.column({ gap = 6, flexGrow = 1 }, { preview }),
    }),
  }
end

local function phpBody()
  local s = st.php
  local empty = trim(s.input) == ""

  local status
  if empty then
    status = nil
  elseif s.err ~= nil then
    status = statusLabel(noctalia.tr("ui.parse_failed"), false)
  else
    status = ui.label({
      text = noctalia.tr("ui.detected") .. ": " .. tostring(s.fmt),
      fontSize = 11,
      color = "success",
      maxLines = 1,
    })
  end

  local bar = toolbarRow({
    {
      key = "php-paste",
      text = noctalia.tr("ui.paste"),
      glyph = "clipboard",
      onClick = function()
        local clip = noctalia.clipboardText()
        if clip == nil or clip == "" then return end
        s.input = clip
        s.nonce = s.nonce + 1
        phpParse()
        render()
      end,
    },
    {
      key = "php-copy",
      text = noctalia.tr("ui.copy"),
      glyph = "copy",
      enabled = not empty and s.err == nil,
      onClick = function()
        noctalia.copyToClipboard(phpLib.serialize(s.value, true), "text/plain")
        noctalia.notify("Dev Utils", "JSON copied")
      end,
    },
    status = status,
  })
  local depthBar = depthControls(s)

  local right
  if empty then
    right = hintRow("brand-php", noctalia.tr("ui.phplang.hint"))
  elseif s.err ~= nil then
    right = errorRow(s.err)
  else
    local rows, truncated = treeLib.render(s.value, s.collapsed, makeToggle(s.collapsed), {
      isNull = phpLib.isNull,
      defaultCollapseDepth = currentDepth(s),
    })
    local kids = {}
    if truncated then
      kids[#kids + 1] = hintRow("alert-triangle", noctalia.tr("ui.truncated_tree", { max = treeLib.MAX_NODES }))
    end
    for _, r in ipairs(rows) do kids[#kids + 1] = r end
    right = ui.scroll({ gap = 0, flexGrow = 1 }, kids)
  end

  return {
    bar,
    ui.row({ gap = 10, flexGrow = 1 }, {
      ui.column({ gap = 6, flexGrow = 1 }, {
        depthBar,
        inputPane("php-input-" .. s.nonce, s.input, "array:2 [▼ …", function(v)
          s.input = v or ""
          schedule("php")
        end),
      }),
      ui.column({ gap = 6, flexGrow = 1 }, { right }),
    }),
  }
end

-- ── Render ───────────────────────────────────────────────────────────────────

local BODIES = {
  json = jsonBody,
  sql = sqlBody,
  markdown = markdownBody,
  php = phpBody,
}

render = function()
  local tabs = {}
  for _, t in ipairs(TOOLS) do
    tabs[#tabs + 1] = ui.button({
      key = "tab-" .. t.id,
      text = noctalia.tr(t.titleKey),
      glyph = t.glyph,
      variant = activeTool == t.id and "primary" or "ghost",
      controlSize = "sm",
      selected = activeTool == t.id,
      onClick = function()
        if activeTool ~= t.id then
          activeTool = t.id
          st.md.clearArmed = false
          render()
        end
      end,
    })
  end

  local body = BODIES[activeTool] or jsonBody
  panel.render(ui.column({ gap = 10, padding = 14, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "tools", size = 15, color = "primary" }),
      ui.label({ text = "Dev Utils", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      ui.spacer({ flexGrow = 1 }),
      table.unpack(tabs),
    }),
    ui.separator({ color = "outline", opacity = 0.2 }),
    ui.column({ gap = 8, flexGrow = 1 }, body()),
  }))
end

function onOpen(_context)
  local t = noctalia.state.get("openTool")
  if t ~= nil and BODIES[t] ~= nil then
    activeTool = t
  end
  lastInputKey = nil -- native controls may be recreated after a close
  panel.setNeedsFrameTick(true) -- resume debounce ticks
  render()
end

-- IPC hook (also used for headless verification):
--   noctalia msg plugin gery/devutils:devutils-panel all <event> [payload]
function onIpc(event, payload)
  if event == "open" then
    if payload ~= nil and BODIES[payload] ~= nil then activeTool = payload end
    render()
  elseif event == "json" then
    st.json.input = payload or ""
    st.json.nonce = st.json.nonce + 1
    jsonParse()
    render()
  elseif event == "php" then
    st.php.input = payload or ""
    st.php.nonce = st.php.nonce + 1
    phpParse()
    render()
  elseif event == "sql" then
    st.sql.input = payload or ""
    st.sql.nonce = st.sql.nonce + 1
    render()
  elseif event == "md" then
    st.md.text = payload or ""
    st.md.nonce = st.md.nonce + 1
    saveScratch()
    render()
  elseif event == "paste" then
    local clip = noctalia.clipboardText()
    if clip ~= nil and clip ~= "" then
      local s = st[activeTool]
      if activeTool == "markdown" then
        s.text = clip
        s.nonce = s.nonce + 1
        saveScratch()
      else
        s.input = clip
        s.nonce = s.nonce + 1
        if activeTool == "json" then jsonParse() elseif activeTool == "php" then phpParse() end
      end
    end
    render()
  elseif event == "format" then
    sqlFormat()
  elseif event == "depth" then
    local s = (activeTool == "php") and st.php or st.json
    s.viewDepth = tonumber(payload) or 99
    s.collapsed = {}
    render()
  end
end

render()
