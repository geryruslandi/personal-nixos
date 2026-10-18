--!nonstrict
-- PHP debug-dump → Lua table for gery/devutils.
-- Autodetects and parses four dump formats, keeping nulls via M.NULL (Lua
-- tables cannot hold nil) and preserving array-vs-object shape:
--   • Laravel/Symfony dd()/dump()  (array:N [▼, ClassName {#id ▼, +prop: …)
--   • PHP native var_dump()        (array(2) {, object(C)#1 (2) {)
--   • print_r()                    (Array ( [k] => v ))
--   • var_export()                 (array ( 'k' => v ), X::__set_state)
-- M.parse(text) → table, formatName  |  nil, error
-- M.serialize(value, pretty) → JSON text (own encoder: null-aware, sorted keys)
--
-- Conventions shared by every parser below:
--   value-fns take (vtext, idx) where idx is the line carrying vtext, and
--   return (value, nextIdx) with nextIdx = first line after the value's
--   lines. Errors are (nil, "line N: …"); success never yields nil
--   (nulls come back as M.NULL).

local M = {}

-- Null sentinel: Lua can't store nil in tables, so parsed nulls carry this
-- marker and the serializer/tree render it back as JSON null.
M.NULL = {}

function M.isNull(v)
  return v == M.NULL
end

-- ── Shared helpers ───────────────────────────────────────────────────────────

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

local function splitLines(text)
  local ls = {}
  for line in (text:gsub("\r\n", "\n"):gmatch("([^\n]*)\n?")) do
    ls[#ls + 1] = line
  end
  return ls
end

local function firstLine(lines)
  local i = 1
  while i <= #lines and trim(lines[i]) == "" do i = i + 1 end
  if i > #lines then return nil end
  return i
end

-- Parsed maps use string keys; decide array (0..n-1 integer keys → Lua list)
-- vs object shape.
local function shapeDecide(t)
  local n, maxK, allInt = 0, -1, true
  for k, _ in pairs(t) do
    n = n + 1
    local kn = tonumber(k)
    if kn == nil or kn ~= math.floor(kn) then
      allInt = false
    elseif kn > maxK then
      maxK = kn
    end
  end
  if allInt and n == 0 then return {} end
  if allInt and maxK == n - 1 then
    local out = {}
    for k = 0, n - 1 do out[k + 1] = t[tostring(k)] end
    return out
  end
  return t
end

local function isNumber(s)
  return s:match("^%-?%d+$") ~= nil or s:match("^%-?%d+%.%d+$") ~= nil
end

-- ── JSON serialization (null-aware, sorted keys) ─────────────────────────────

local function escJson(s)
  return '"'
    .. s:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' end
      if c == "\\" then return "\\\\" end
      if c == "\n" then return "\\n" end
      if c == "\t" then return "\\t" end
      if c == "\r" then return "\\r" end
      return string.format("\\u%04x", string.byte(c))
    end)
    .. '"'
end

local function sortedKeys(t)
  local ks = {}
  for k, _ in pairs(t) do ks[#ks + 1] = tostring(k) end
  table.sort(ks)
  return ks
end

-- indent == nil → compact single line
function M.serialize(v, indent)
  local IND = "  "
  local ser
  local function pad(depth)
    return "\n" .. IND:rep(depth)
  end

  ser = function(v, depth)
    if M.isNull(v) then return "null" end
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then return tostring(v) end
    if t == "string" then return escJson(v) end
    if t ~= "table" then return escJson(tostring(v)) end

    local isArray, n = true, 0
    for k, _ in pairs(v) do
      if type(k) ~= "number" then isArray = false end
      n = n + 1
    end
    if n == 0 then return "[]" end

    if isArray then
      local parts = {}
      for i = 1, n do parts[i] = ser(v[i], depth + 1) end
      if indent == nil then return "[" .. table.concat(parts, ",") .. "]" end
      return "[" .. pad(depth + 1) .. table.concat(parts, "," .. pad(depth + 1)) .. pad(depth) .. "]"
    end

    local parts = {}
    for _, k in ipairs(sortedKeys(v)) do
      parts[#parts + 1] = escJson(k) .. (indent and ": " or ":") .. ser(v[k], depth + 1)
    end
    if indent == nil then return "{" .. table.concat(parts, ",") .. "}" end
    return "{" .. pad(depth + 1) .. table.concat(parts, "," .. pad(depth + 1)) .. pad(depth) .. "}"
  end

  return ser(v, 0)
end

-- ── Laravel / Symfony VarDumper (dd / dump) ──────────────────────────────────

local function symUnquote(s)
  local inner = s:match('^"(.*)"$')
  if inner == nil then return s end
  return (inner:gsub('\\"', '"'):gsub("\\\\", "\\"))
end

local function symKey(k)
  if k:sub(1, 1) == '"' then return symUnquote(k) end
  return k
end

local function parseSymfony(lines)
  local symArray, symObject, symValue -- forward

  symValue = function(vtext, idx)
    if vtext == "" then return M.NULL, idx + 1 end
    if vtext:sub(1, 1) == '"' then return symUnquote(vtext), idx + 1 end
    if vtext == "…" or vtext:find("▶", 1, true) then return "…", idx + 1 end -- folded/truncated
    vtext = (vtext:gsub("%s*▼%s*$", ""))
    local count = vtext:match("^array:(%d+)")
    if count then return symArray(idx + 1) end
    local cls, id = vtext:match("^(.-)%s*{#(%d+)%s*$")
    if cls == nil then
      local idOnly = vtext:match("^{#(%d+)}")
      if idOnly then return symObject(idx + 1, "stdClass", idOnly) end
    end
    if cls then return symObject(idx + 1, cls, id) end
    if vtext == "true" then return true, idx + 1 end
    if vtext == "false" then return false, idx + 1 end
    if vtext == "null" or vtext == "NULL" then return M.NULL, idx + 1 end
    if isNumber(vtext) then return tonumber(vtext), idx + 1 end
    return vtext, idx + 1 -- enums, class refs, *RECURSION*, anything else
  end

  symArray = function(start)
    local i, t = start, {}
    while i <= #lines do
      local raw = trim(lines[i])
      if raw == "]" then return shapeDecide(t), i + 1 end
      if raw ~= "" then
        local key, value, ni
        local prop, vtext = raw:match("^[%+%-#]([%w_]+):%s*(.*)$")
        if prop then
          key = prop
          value, ni = symValue(vtext, i)
        else
          local k, v = raw:match("^(.-)%s*=>%s*(.*)$")
          if k == nil then return nil, "line " .. i .. ": cannot parse element: " .. raw end
          key = symKey(trim(k))
          value, ni = symValue(v, i)
        end
        if value == nil then return nil, ni end
        t[key] = value
        i = ni
      else
        i = i + 1
      end
    end
    return nil, "unterminated array (missing ])"
  end

  symObject = function(start, cls, id)
    local i, t = start, {}
    while i <= #lines do
      local raw = trim(lines[i])
      if raw == "}" then
        if cls ~= nil and cls ~= "" and cls ~= "stdClass" then t["@class"] = cls end
        if id then t["@id"] = tonumber(id) end
        return t, i + 1
      end
      if raw ~= "" then
        local prop, vtext = raw:match("^[%+%-#]([%w_]+):%s*(.*)$")
        if prop == nil then return nil, "line " .. i .. ": cannot parse property: " .. raw end
        local value, ni = symValue(vtext, i)
        if value == nil then return nil, ni end
        t[prop] = value
        i = ni
      else
        i = i + 1
      end
    end
    return nil, "unterminated object (missing })"
  end

  local first = firstLine(lines)
  if first == nil then return nil, "empty input" end
  local vtext = trim(lines[first])
  vtext = (vtext:gsub("%s*▼%s*$", ""))
  local count = vtext:match("^array:(%d+)")
  if count then return symArray(first + 1) end
  local cls, id = vtext:match("^(.-)%s*{#(%d+)%s*$")
  if cls then return symObject(first + 1, cls, id) end
  return symValue(vtext, first)
end

-- ── var_dump ─────────────────────────────────────────────────────────────────

local function parseVarDump(lines)
  local vdValue, vdContainer -- forward

  vdContainer = function(openerIdx)
    local opener = trim(lines[openerIdx])
    local cls = opener:match("^object%((.-)%)#%d+ %(%d+%) %{")
    local i, t = openerIdx + 1, {}
    while i <= #lines do
      local raw = trim(lines[i])
      if raw == "}" then
        local out = shapeDecide(t)
        if cls ~= nil and cls ~= "stdClass" then out["@class"] = cls end
        return out, i + 1
      end
      if raw ~= "" then
        local key = raw:match("^%[(.-)%]%s*=>")
        if key == nil then return nil, "line " .. i .. ": expected [key]=>, got: " .. raw end
        key = (key:gsub('"', "")) -- ["id"] and ["id":protected] alike
        key = (key:gsub(":%w+$", "")) -- drop :protected/:private/:public suffix
        i = i + 1
        local vraw
        while i <= #lines do
          local l = trim(lines[i])
          if l ~= "" then vraw = l break end
          i = i + 1
        end
        if vraw == nil then return nil, "unexpected end after [" .. key .. "]=>" end
        local value, ni = vdValue(vraw, i)
        if value == nil then return nil, ni end
        t[key] = value
        i = ni
      else
        i = i + 1
      end
    end
    return nil, "unterminated container (missing })"
  end

  vdValue = function(vraw, idx)
    if vraw:match("^string%(%d+%)") then
      local a = vraw:find('"', 1, true)
      if a then
        local b
        for j = #vraw, a + 1, -1 do
          if vraw:sub(j, j) == '"' then b = j break end
        end
        if b and b > a then return vraw:sub(a + 1, b - 1), idx + 1 end
      end
      return "", idx + 1
    end
    local n = vraw:match("^int%((%-?%d+)%)")
    if n then return tonumber(n), idx + 1 end
    local f = vraw:match("^float%((.-)%)")
    if f then
      local fv = tonumber(f)
      if fv then return fv, idx + 1 end
      return f, idx + 1 -- NAN / INF
    end
    local b = vraw:match("^bool%((%a+)%)")
    if b then return b == "true", idx + 1 end
    if vraw == "NULL" then return M.NULL, idx + 1 end
    if vraw:match("^array%(%d+%) %{") then return vdContainer(idx) end
    if vraw:match("^object%(.-%)#%d+ %(%d+%) %{") then return vdContainer(idx) end
    local rt = vraw:match("^resource%(%d+%) of type %((.-)%)")
    if rt then return "resource(" .. rt .. ")", idx + 1 end
    return vraw, idx + 1
  end

  local first = firstLine(lines)
  if first == nil then return nil, "empty input" end
  local vraw = trim(lines[first])
  if vraw:match("^array%(%d+%) %{") or vraw:match("^object%(.-%)#%d+ %(%d+%) %{") then
    return vdContainer(first)
  end
  return vdValue(vraw, first)
end

-- ── print_r ──────────────────────────────────────────────────────────────────

local function parsePrintR(lines)
  local prValue, prContainer -- forward

  prContainer = function(parenIdx)
    if trim(lines[parenIdx] or "") ~= "(" then
      return nil, "line " .. parenIdx .. ": expected ("
    end
    local i, t = parenIdx + 1, {}
    while i <= #lines do
      local raw = trim(lines[i])
      if raw == ")" then return shapeDecide(t), i + 1 end
      if raw ~= "" then
        local key, vtext = raw:match("^%[(.-)%]%s*=>%s*(.*)$")
        if key == nil then return nil, "line " .. i .. ": expected [key] => value, got: " .. raw end
        local value, ni = prValue(vtext, i + 1)
        if value == nil then return nil, ni end
        t[key] = value
        i = ni
      else
        i = i + 1
      end
    end
    return nil, "unterminated container (missing })"
  end

  -- vtext was on line idx-1 (already consumed); a container opens on line idx.
  prValue = function(vtext, idx)
    if vtext == "" or vtext == nil then return M.NULL, idx end
    if vtext == "Array" then return prContainer(idx) end
    local cls = vtext:match("^([%w\\]+)%s+Object%s*$")
    if cls then
      local v, ni = prContainer(idx)
      if v ~= nil and cls ~= "stdClass" then v["@class"] = cls end
      return v, ni
    end
    -- NOTE: print_r renders true as `1` (indistinguishable from int 1), and
    -- false as an empty value (→ null). Numbers win so int values stay ints.
    if isNumber(vtext) then return tonumber(vtext), idx end
    return vtext, idx -- raw (unquoted) string
  end

  local first = firstLine(lines)
  if first == nil then return nil, "empty input" end
  return prValue(trim(lines[first]), first + 1)
end

-- ── var_export ───────────────────────────────────────────────────────────────

local function parseVarExport(lines)
  local veValue, veArray -- forward

  local function veUnquote(s)
    local inner = s:match("^'(.*)'$")
    if inner == nil then return s end
    return (inner:gsub("\\'", "'"):gsub("\\\\", "\\"))
  end

  -- Items start at line `start` (the opener line was already consumed).
  veArray = function(start)
    local i, t = start, {}
    while i <= #lines do
      local raw = trim(lines[i])
      if raw:match("^%)+,?%s*$") then return shapeDecide(t), i + 1 end
      if raw ~= "" then
        -- Greedy `.*`: the key's closing quote sits right before ` => `.
        local key, vtext = raw:match("^'(.*)'%s*=>%s*(.*)$")
        if key ~= nil then
          key = key:gsub("\\'", "'"):gsub("\\\\", "\\")
        else
          key, vtext = raw:match("^(%d+)%s*=>%s*(.*)$")
        end
        if key == nil then return nil, "line " .. i .. ": cannot parse item: " .. raw end
        -- Items are comma-terminated; strip one trailing comma.
        vtext = (vtext:match("^(.*),%s*$") or vtext)
        local value, ni
        if vtext == "" then
          value, ni = veValue(trim(lines[i + 1] or ""), i + 1)
        else
          value, ni = veValue(vtext, i)
        end
        if value == nil then return nil, ni end
        t[key] = value
        i = ni
      else
        i = i + 1
      end
    end
    return nil, "unterminated array (missing )"
  end

  veValue = function(vtext, idx)
    if vtext == "" then return M.NULL, idx + 1 end
    if vtext:sub(1, 1) == "'" then return veUnquote(vtext), idx + 1 end
    if vtext == "true" then return true, idx + 1 end
    if vtext == "false" then return false, idx + 1 end
    if vtext == "NULL" or vtext == "null" then return M.NULL, idx + 1 end
    if isNumber(vtext) then return tonumber(vtext), idx + 1 end
    local cls = vtext:match("^([%w\\]+)::__set_state%(array%($")
    if cls then
      local v, ni = veArray(idx + 1)
      if v ~= nil and cls ~= "stdClass" then v["@class"] = cls end
      return v, ni
    end
    if vtext == "array (" then return veArray(idx + 1) end
    return vtext, idx + 1
  end

  local first = firstLine(lines)
  if first == nil then return nil, "empty input" end
  local vtext = trim(lines[first])
  if vtext == "array (" then return veArray(first + 1) end
  return veValue(vtext, first)
end

-- ── Detection & entry point ──────────────────────────────────────────────────

M.FORMATS = { "var_dump", "print_r", "var_export", "symfony" }

function M.detect(text)
  local lines = splitLines(text or "")
  local checked = 0
  for i = 1, #lines do
    local l = trim(lines[i])
    if l ~= "" then
      checked = checked + 1
      if checked > 40 then break end
      if l:match("^array%(%d+%) %{")
        or l:match("^object%(.-%)#%d+ %(%d+%) %{")
        or l:match("^string%(%d+%)")
        or l:match("^int%(") or l:match("^float%(")
        or l:match("^bool%(") or l:match("^resource%(")
        or l == "NULL"
      then
        return "var_dump"
      end
      if l == "Array" or l:match("[\\%w_]+%s+Object%s*$") then
        return "print_r"
      end
      if l:match("^array %(") or l:find("__set_state", 1, true) then
        return "var_export"
      end
      if l:match("^array:%d+") or l:match("{#%d+}") or l:match("[\\%w_]+ {%#%d+") then
        return "symfony"
      end
    end
  end
  return "symfony" -- bare scalars (dd("x")) are Symfony-style
end

-- Returns table, formatName | nil, error
function M.parse(text)
  if trim(text or "") == "" then return nil, "empty input" end

  -- Guard: plain JSON is not a PHP dump.
  local c = trim(text)
  if c:sub(1, 1) == "{" or c:sub(1, 1) == "[" then
    local decoded = noctalia.json.decode(c)
    if decoded ~= nil then
      return nil, "input is already valid JSON — use the JSON Formatter tab"
    end
  end

  local lines = splitLines(text)
  local fmt = M.detect(text)
  local parsers = {
    var_dump = parseVarDump,
    print_r = parsePrintR,
    var_export = parseVarExport,
    symfony = parseSymfony,
  }
  local value, second = parsers[fmt](lines)
  if value == nil then return nil, second end
  return value, fmt
end

return M
