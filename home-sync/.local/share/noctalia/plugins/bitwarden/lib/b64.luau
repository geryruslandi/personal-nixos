--!nonstrict
-- Base64 encoding for `bw create` / `bw send create` (the CLI takes the
-- JSON object base64-encoded; `bw encode` only reads stdin, so encode here).

local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.encode(s)
  local out = {}
  local n = #s
  local i = 1
  while i <= n do
    local b1 = string.byte(s, i)
    local b2 = i + 1 <= n and string.byte(s, i + 1) or nil
    local b3 = i + 2 <= n and string.byte(s, i + 2) or nil
    local c1 = math.floor(b1 / 4)
    local c2 = (b1 % 4) * 16 + (b2 and math.floor(b2 / 16) or 0)
    local c3 = b2 and ((b2 % 16) * 4 + (b3 and math.floor(b3 / 64) or 0)) or nil
    local c4 = b3 and (b3 % 64) or nil
    out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1)
    out[#out + 1] = ALPHABET:sub(c2 + 1, c2 + 1)
    out[#out + 1] = c3 and ALPHABET:sub(c3 + 1, c3 + 1) or "="
    out[#out + 1] = c4 and ALPHABET:sub(c4 + 1, c4 + 1) or "="
    i += 3
  end
  return table.concat(out)
end

return M
