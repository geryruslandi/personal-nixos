--!nonstrict
-- Plugin settings helpers (read live via noctalia.getConfig) and the
-- `bw generate` argument builder shared by the service and generator panel.

local M = {}

function M.get(key)
  return noctalia.getConfig(key)
end

function M.str(key, default)
  local v = noctalia.getConfig(key)
  if type(v) == "string" then
    return v
  end
  return default
end

function M.bool(key, default)
  local v = noctalia.getConfig(key)
  if type(v) == "boolean" then
    return v
  end
  return default
end

function M.int(key, default, min, max)
  local v = noctalia.getConfig(key)
  if type(v) ~= "number" then
    v = default
  end
  v = math.floor(v)
  if min ~= nil and v < min then
    v = min
  end
  if max ~= nil and v > max then
    v = max
  end
  return v
end

-- Vault re-lock timeout in minutes; nil = never.
function M.timeoutMinutes()
  local mode = M.str("vault_timeout", "on_restart")
  if mode == "never" or mode == "on_restart" then
    return nil
  end
  if mode == "custom" then
    return M.int("vault_timeout_custom_minutes", 15, 1, 10080)
  end
  local minutes = tonumber(mode)
  if minutes == nil or minutes <= 0 then
    return nil
  end
  return math.floor(minutes)
end

function M.generatorDefaults()
  return {
    mode = "password",
    length = M.int("gen_length", 14, 5, 128),
    upper = M.bool("gen_uppercase", true),
    lower = M.bool("gen_lowercase", true),
    number = M.bool("gen_number", false),
    special = M.bool("gen_special", false),
    words = M.int("gen_passphrase_words", 3, 3, 20),
    separator = M.str("gen_passphrase_separator", "-"),
    capitalize = M.bool("gen_passphrase_capitalize", false),
    includeNumber = M.bool("gen_passphrase_include_number", false),
  }
end

function M.generateArgs(opts)
  opts = opts or M.generatorDefaults()
  local args = { "generate" }
  if opts.mode == "passphrase" or opts.passphrase == true then
    table.insert(args, "--passphrase")
    table.insert(args, "--words")
    table.insert(args, tostring(M.clampWords(opts.words)))
    local sep = opts.separator
    if type(sep) ~= "string" or sep == "" then
      sep = "-"
    end
    table.insert(args, "--separator")
    table.insert(args, sep)
    if opts.capitalize == true then
      table.insert(args, "--capitalize")
    end
    if opts.includeNumber == true then
      table.insert(args, "--includeNumber")
    end
    return args
  end
  table.insert(args, "--length")
  table.insert(args, tostring(M.clampLength(opts.length)))
  local upper = opts.upper == true
  local lower = opts.lower == true
  local number = opts.number == true
  local special = opts.special == true
  if not upper and not lower and not number and not special then
    lower = true
  end
  if upper then
    table.insert(args, "--uppercase")
  end
  if lower then
    table.insert(args, "--lowercase")
  end
  if number then
    table.insert(args, "--number")
  end
  if special then
    table.insert(args, "--special")
  end
  return args
end

function M.clampLength(v)
  v = tonumber(v) or 14
  v = math.floor(v)
  return math.clamp(v, 5, 128)
end

function M.clampWords(v)
  v = tonumber(v) or 3
  v = math.floor(v)
  return math.clamp(v, 3, 20)
end

return M
