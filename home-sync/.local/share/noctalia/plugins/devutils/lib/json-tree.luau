--!nonstrict
-- JSON tree utilities for gery/devutils: a whitespace-preserving pretty
-- printer (own tokenizer — noctalia.json.decode loses `null` values and key
-- order, and the copy button must round-trip faithfully) and the collapsible
-- ui.* tree renderer shared by the JSON tool and the PHP dump tool.

local M = {}

M.MAX_NODES = 1500
M.MAX_INLINE = 80

M.COLOR = {
  string = "success",
  number = "primary",
  boolean = "warning",
  null = "on_surface_variant",
  key = "on_surface",
  punct = "on_surface_variant",
}

M.FONT_SIZE = 12

-- ── Low-level scanning ───────────────────────────────────────────────────────

local function isSpace(c)
  return c == " " or c == "\t" or c == "\n" or c == "\r"
end

-- s[i] must be '"'; returns the index of the closing quote (or nil).
local function scanString(s, i)
  local j = i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then
      j = j + 2
    elseif c == '"' then
      return j
    else
      j = j + 1
    end
  end
  return nil
end

-- s[i] must be '{' or '['; returns the index of the matching closer (or nil).
-- initialDepth = 1 when called from just inside a container (opener consumed).
local function scanContainer(s, i, initialDepth)
  local depth = initialDepth or 0
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      local j = scanString(s, i)
      if j == nil then return nil end
      i = j + 1
    elseif c == "{" or c == "[" then
      depth = depth + 1
      i = i + 1
    elseif c == "}" or c == "]" then
      depth = depth - 1
      if depth == 0 then return i end
      i = i + 1
    else
      i = i + 1
    end
  end
  return nil
end

-- Strip whitespace outside strings so an inline segment can sit on one line.
local function compact(seg)
  local out = {}
  local k = 1
  while k <= #seg do
    local c = seg:sub(k, k)
    if c == '"' then
      local j = scanString(seg, k)
      if j == nil then return seg end
      out[#out + 1] = seg:sub(k, j)
      k = j + 1
    elseif isSpace(c) then
      k = k + 1
    else
      out[#out + 1] = c
      k = k + 1
    end
  end
  return table.concat(out)
end

-- ── Pretty printer ───────────────────────────────────────────────────────────

-- Returns pretty text, or nil + error message.
function M.pretty(text)
  local s = text or ""
  local i = 1
  local out = {}
  local err = nil
  local INDENT = "  "

  local function skipWs()
    while i <= #s and isSpace(s:sub(i, i)) do i = i + 1 end
  end

  local function emit(t) out[#out + 1] = t end
  local function newline(depth) emit("\n" .. INDENT:rep(depth)) end

  local function readString()
    local j = scanString(s, i)
    if j == nil then
      err = "unterminated string at char " .. i
      return nil
    end
    local str = s:sub(i, j)
    i = j + 1
    return str
  end

  local function readLiteral()
    local j = i
    while j <= #s do
      local c = s:sub(j, j)
      if c:match("[%w%+%-%.eE]") then
        j = j + 1
      else
        break
      end
    end
    local lit = s:sub(i, j - 1)
    i = j
    return lit
  end

  local parseValue -- forward

  local function inlineCandidate(openIdx)
    local closeIdx = scanContainer(s, i, 1)
    if closeIdx == nil then
      err = "unclosed container at char " .. i
      return nil
    end
    local seg = s:sub(openIdx, closeIdx)
    -- Nested container inside → never inline. (Find past the opener.)
    if seg:find("{", 2) or seg:find("%[", 2) then return nil end
    if #seg > M.MAX_INLINE then return nil end
    return seg, closeIdx
  end

  local function parseContainer(open, depth)
    local close = (open == "{") and "}" or "]"
    local openIdx = i
    i = i + 1 -- consume opener
    skipWs()
    if s:sub(i, i) == close then
      i = i + 1
      emit(open .. close)
      return
    end
    local seg, closeIdx = inlineCandidate(openIdx)
    if seg ~= nil then
      emit(compact(seg))
      i = closeIdx + 1
      return
    end
    if err ~= nil then return end
    emit(open)
    newline(depth + 1)
    while true do
      skipWs()
      local c = s:sub(i, i)
      if c == "" then
        err = "unclosed container (missing " .. close .. ")"
        return
      end
      if c == close then
        i = i + 1
        newline(depth)
        emit(close)
        return
      end
      if open == "{" then
        skipWs()
        local key = readString()
        if key == nil then return end
        emit(key)
        skipWs()
        if s:sub(i, i) ~= ":" then
          err = 'expected ":" after key at char ' .. i
          return
        end
        i = i + 1
        emit(": ")
        parseValue(depth + 1)
      else
        parseValue(depth + 1)
      end
      if err ~= nil then return end
      skipWs()
      if s:sub(i, i) == "," then
        i = i + 1
        emit(",")
        newline(depth + 1)
      end
    end
  end

  parseValue = function(depth)
    skipWs()
    local c = s:sub(i, i)
    if c == "" then
      err = "unexpected end of input"
      return
    end
    if c == "{" or c == "[" then
      parseContainer(c, depth)
    elseif c == '"' then
      local str = readString()
      if str == nil then return end
      emit(str)
    elseif c == "}" or c == "]" or c == "," or c == ":" then
      err = "unexpected '" .. c .. "' at char " .. i
    else
      emit(readLiteral())
    end
  end

  parseValue(0)
  if err ~= nil then return nil, err end
  skipWs()
  if i <= #s then return nil, "trailing content at char " .. i end
  return table.concat(out)
end

-- ── Decoding (for the tree) ──────────────────────────────────────────────────

-- Returns ok, value | nil, err
function M.decode(text)
  local value = noctalia.json.decode(text or "")
  if value == nil then return false, "not valid JSON" end
  return true, value
end

-- Lua-table classification ---------------------------------------------------

function M.isArray(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == 0 or n == #t
end

local function keyLess(a, b)
  return a:lower() < b:lower()
end

function M.summaryFor(value)
  if type(value) ~= "table" then return "" end
  if M.isArray(value) then
    return "[…] " .. #value .. " " .. noctalia.tr("ui.items")
  end
  local n = 0
  for _ in pairs(value) do n = n + 1 end
  return "{…} " .. n .. " " .. noctalia.tr("ui.keys")
end

-- ── Tree renderer ────────────────────────────────────────────────────────────
-- Returns a children array for ui.scroll plus a `truncated` flag.

function M.render(value, collapsed, onToggle, opts)
  opts = opts or {}
  local fs = opts.fontSize or M.FONT_SIZE
  local maxNodes = opts.maxNodes or M.MAX_NODES
  local counter = { n = 0, truncated = false }

  local function leafText(v)
    local t = type(v)
    if t == "string" then
      return '"' .. v .. '"', M.COLOR.string
    elseif t == "number" then
      return tostring(v), M.COLOR.number
    elseif t == "boolean" then
      return tostring(v), M.COLOR.boolean
    end
    return "null", M.COLOR.null
  end

  local function leafRow(path, keyText, isArrKey, v)
    local text, color = leafText(v)
    local kids = {
      ui.glyph({ name = "point", size = 9, color = "outline" }),
    }
    if keyText ~= nil then
      kids[#kids + 1] = ui.label({
        text = keyText,
        fontSize = fs,
        color = isArrKey and M.COLOR.punct or M.COLOR.key,
        maxLines = 1,
      })
    end
    kids[#kids + 1] = ui.label({ text = text, fontSize = fs, color = color, maxLines = 1, flexGrow = 1 })
    return ui.row({ key = "t" .. path, gap = 5, align = "center", paddingV = 1 }, kids)
  end

  local function build(v, path, keyText, isArrKey, rows, depth)
    counter.n = counter.n + 1
    if counter.n > maxNodes then
      counter.truncated = true
      return
    end

    -- PHP dump nulls arrive as a sentinel table (Lua has no nil values).
    if opts.isNull and opts.isNull(v) then
      rows[#rows + 1] = leafRow(path, keyText, isArrKey, v)
      return
    end

    if type(v) ~= "table" then
      rows[#rows + 1] = leafRow(path, keyText, isArrKey, v)
      return
    end

    local isArray = M.isArray(v)
    local count = isArray and #v or (function()
      local n = 0
      for _ in pairs(v) do n = n + 1 end
      return n
    end)()

    if count == 0 then
      -- Empty container: leaf with `{}` / `[]`, no expander.
      local kids = {
        ui.glyph({ name = "point", size = 9, color = "outline" }),
      }
      if keyText ~= nil then
        kids[#kids + 1] = ui.label({
          text = keyText,
          fontSize = fs,
          color = isArrKey and M.COLOR.punct or M.COLOR.key,
          maxLines = 1,
        })
      end
      kids[#kids + 1] = ui.label({
        text = isArray and "[]" or "{}",
        fontSize = fs,
        color = M.COLOR.punct,
        maxLines = 1,
        flexGrow = 1,
      })
      rows[#rows + 1] = ui.row({ key = "t" .. path, gap = 5, align = "center", paddingV = 1 }, kids)
      return
    end

    local isCollapsed = collapsed[path] == true

    -- Branch header
    local head = {
      ui.glyph({
        name = isCollapsed and "chevron-right" or "chevron-down",
        size = 11,
        color = M.COLOR.punct,
      }),
    }
    if keyText ~= nil then
      head[#head + 1] = ui.label({
        text = keyText,
        fontSize = fs,
        color = isArrKey and M.COLOR.punct or M.COLOR.key,
        maxLines = 1,
      })
    end
    if isCollapsed then
      head[#head + 1] = ui.label({ text = M.summaryFor(v), fontSize = fs, color = M.COLOR.punct, maxLines = 1 })
    end
    rows[#rows + 1] = ui.row({
      key = "t" .. path,
      gap = 5,
      align = "center",
      paddingV = 1,
      onClick = function() onToggle(path) end,
    }, head)

    if isCollapsed then return end

    -- Children
    local childRows = {}
    local keys
    if isArray then
      keys = {}
      for k = 1, #v do keys[k] = k end
    else
      keys = {}
      for k, _ in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys, keyLess)
    end
    for _, k in ipairs(keys) do
      local child = v[k]
      local childPath = isArray and (path .. "[" .. k .. "]") or (path .. "." .. tostring(k))
      local childKey = isArray and ("[" .. tostring(k) .. "]") or ('"' .. tostring(k) .. '":')
      local before = #childRows
      build(child, childPath, childKey, isArray, childRows, depth + 1)
      if #childRows == before then break end -- node budget exhausted
    end
    rows[#rows + 1] = ui.column({ key = "c" .. path, paddingH = 14, gap = 0 }, childRows)
  end

  local rows = {}
  build(value, "$", nil, false, rows, 0)
  return rows, counter.truncated
end

return M
