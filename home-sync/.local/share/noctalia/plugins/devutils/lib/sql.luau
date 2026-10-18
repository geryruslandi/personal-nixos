--!nonstrict
-- pg_format driver for gery/devutils. noctalia.runAsync has no stdin, so the
-- SQL goes to a temp file in the plugin data dir and pg_format writes the
-- result to a second file (positional input + --output → no shell quoting).

local M = {}

M.IN_FILE = "sql-in.tmp"
M.OUT_FILE = "sql-out.tmp"

local function cfg(key, def)
  local v = noctalia.getConfig(key)
  if v == nil or v == "" then return def end
  return v
end

-- The runAsync subprocess may not inherit the user PATH, so bare binary names
-- are resolved to an absolute path first (same approach as gery/services).
function M.expandBinary(binary)
  if string.sub(binary, 1, 1) == "/" then return binary end
  local path = noctalia.expandPath(binary)
  if path and noctalia.fileExists(path) then return path end
  local envPath = noctalia.getenv("PATH") or ""
  for dir in string.gmatch(envPath .. ":", "([^:]*):") do
    if #dir > 0 then
      local candidate = dir .. "/" .. binary
      if noctalia.fileExists(candidate) then return candidate end
    end
  end
  return nil, "not found on PATH: " .. binary
end

-- M.format(sql, cb): cb(ok, outputOrError)
--   ok=true  → output = formatted SQL
--   ok=false → output = error message
function M.format(sql, cb)
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    cb(false, "plugin data dir unavailable")
    return
  end

  local bin = cfg("sql_binary", "pg_format")
  local resolved, err = M.expandBinary(bin)
  if resolved == nil then
    cb(false, noctalia.tr("ui.sql_missing"))
    return
  end

  local indent = tostring(cfg("sql_indent", "2"))
  if indent:match("^%d+$") == nil or tonumber(indent) < 1 or tonumber(indent) > 16 then
    indent = "2"
  end
  -- pg_format --keyword-case: 0 unchanged, 1 lower, 2 upper, 3 capitalize
  local kwcase = tostring(cfg("sql_keyword_case", "2"))
  if kwcase:match("^[0-3]$") == nil then kwcase = "2" end

  local inPath = dir .. "/" .. M.IN_FILE
  local outPath = dir .. "/" .. M.OUT_FILE

  local ok = noctalia.writeFile(inPath, sql)
  if not ok then
    cb(false, "could not write " .. inPath)
    return
  end
  noctalia.removeFile(outPath) -- best effort: drop stale results

  local accepted = noctalia.runAsync({
    resolved,
    "--spaces", indent,
    "--keyword-case", kwcase,
    "--output", outPath,
    inPath,
  }, function(result)
    result = result or {}
    if result.exitCode ~= 0 then
      local msg = (result.stderr ~= nil and result.stderr ~= "") and result.stderr or result.stdout
      if msg == nil or msg == "" then msg = "pg_format exited with code " .. tostring(result.exitCode) end
      cb(false, msg)
      return
    end
    local out, rerr = noctalia.readFile(outPath)
    if out == nil then
      cb(false, "could not read pg_format output: " .. tostring(rerr))
      return
    end
    cb(true, out)
  end)

  if not accepted then
    cb(false, "could not spawn pg_format")
  end
end

return M
