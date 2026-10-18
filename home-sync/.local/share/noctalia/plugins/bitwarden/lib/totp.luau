--!nonstrict
-- Pure-Luau TOTP (RFC 6238) used by the authenticator view.
--
-- Bitwarden stores `login.totp` either as a bare base32 secret, an
-- `otpauth://totp/...` URI or a `steam://SECRET` key. Codes are computed
-- locally so the launcher can render live codes for every item without
-- spawning `bw` per item per second.
--
-- HMAC-SHA1 and HMAC-SHA256 are implemented here; SHA512 has no local
-- implementation (callers fall back to `bw get totp`).

local M = {}

local function band(...)
  return bit32.band(...)
end

local function add32(...)
  local sum = 0
  for _, v in ipairs({ ... }) do
    sum = sum + v
  end
  return bit32.band(sum, 0xFFFFFFFF)
end

local function lrot(x, n)
  return bit32.band(bit32.lshift(x, n) + bit32.rshift(x, 32 - n), 0xFFFFFFFF)
end

local function rrot(x, n)
  return bit32.band(bit32.rshift(x, n) + bit32.lshift(x, 32 - n), 0xFFFFFFFF)
end

local function bytesToString(bytes)
  local chars = table.create(#bytes)
  for i = 1, #bytes do
    chars[i] = string.char(bytes[i])
  end
  return table.concat(chars)
end

local function toHex(bytes)
  local out = {}
  for i = 1, #bytes do
    out[i] = string.format("%02x", bytes[i])
  end
  return table.concat(out)
end

local function stringToBytes(s)
  local bytes = table.create(#s)
  for i = 1, #s do
    bytes[i] = string.byte(s, i)
  end
  return bytes
end

local function u32be(n)
  n = n % 4294967296
  return string.char(
    math.floor(n / 16777216) % 256,
    math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256,
    n % 256
  )
end

-- ── SHA1 ─────────────────────────────────────────────────────────────────────

local function sha1(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #msg
  local bitLen = len * 8
  msg = msg
    .. "\128"
    .. string.rep("\0", (55 - len % 64) % 64)
    .. u32be(math.floor(bitLen / 4294967296))
    .. u32be(bitLen)

  for chunk = 0, #msg / 64 - 1 do
    local w = table.create(80)
    local base = chunk * 64
    for j = 0, 15 do
      local o = base + j * 4
      w[j] = string.byte(msg, o + 1) * 16777216
        + string.byte(msg, o + 2) * 65536
        + string.byte(msg, o + 3) * 256
        + string.byte(msg, o + 4)
    end
    for j = 16, 79 do
      w[j] = lrot(bit32.bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for j = 0, 79 do
      local f, k
      if j < 20 then
        f = bit32.bor(bit32.band(b, c), bit32.band(bit32.bnot(b), d))
        k = 0x5A827999
      elseif j < 40 then
        f = bit32.bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif j < 60 then
        f = bit32.bor(bit32.band(b, c), bit32.band(b, d), bit32.band(c, d))
        k = 0x8F1BBCDC
      else
        f = bit32.bxor(b, c, d)
        k = 0xCA62C1D6
      end
      local temp = add32(lrot(a, 5), f, e, k, w[j])
      e = d
      d = c
      c = lrot(b, 30)
      b = a
      a = temp
    end
    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
  end

  return {
    math.floor(h0 / 16777216) % 256,
    math.floor(h0 / 65536) % 256,
    math.floor(h0 / 256) % 256,
    h0 % 256,
    math.floor(h1 / 16777216) % 256,
    math.floor(h1 / 65536) % 256,
    math.floor(h1 / 256) % 256,
    h1 % 256,
    math.floor(h2 / 16777216) % 256,
    math.floor(h2 / 65536) % 256,
    math.floor(h2 / 256) % 256,
    h2 % 256,
    math.floor(h3 / 16777216) % 256,
    math.floor(h3 / 65536) % 256,
    math.floor(h3 / 256) % 256,
    h3 % 256,
    math.floor(h4 / 16777216) % 256,
    math.floor(h4 / 65536) % 256,
    math.floor(h4 / 256) % 256,
    h4 % 256,
  }
end

-- ── SHA256 ───────────────────────────────────────────────────────────────────

local K256 = {
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
  0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
  0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
  0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
  0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
  0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
}

local function sha256(msg)
  local h = {
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  }
  local len = #msg
  local bitLen = len * 8
  msg = msg
    .. "\128"
    .. string.rep("\0", (55 - len % 64) % 64)
    .. u32be(math.floor(bitLen / 4294967296))
    .. u32be(bitLen)

  local function bsig0(x)
    return bit32.bxor(rrot(x, 7), rrot(x, 18), bit32.rshift(x, 3))
  end
  local function bsig1(x)
    return bit32.bxor(rrot(x, 17), rrot(x, 19), bit32.rshift(x, 10))
  end
  local function ssig0(x)
    return bit32.bxor(rrot(x, 2), rrot(x, 13), rrot(x, 22))
  end
  local function ssig1(x)
    return bit32.bxor(rrot(x, 6), rrot(x, 11), rrot(x, 25))
  end

  for chunk = 0, #msg / 64 - 1 do
    local w = table.create(64)
    local base = chunk * 64
    for j = 0, 15 do
      local o = base + j * 4
      w[j] = string.byte(msg, o + 1) * 16777216
        + string.byte(msg, o + 2) * 65536
        + string.byte(msg, o + 3) * 256
        + string.byte(msg, o + 4)
    end
    for j = 16, 63 do
      w[j] = add32(bsig1(w[j - 2]), w[j - 7], bsig0(w[j - 15]), w[j - 16])
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for j = 0, 63 do
      local t1 = add32(hh, ssig1(e), bit32.bor(bit32.band(e, f), bit32.band(bit32.bnot(e), g)), K256[j + 1], w[j])
      local t2 = add32(ssig0(a), bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c)))
      hh = g
      g = f
      f = e
      e = add32(d, t1)
      d = c
      c = b
      b = a
      a = add32(t1, t2)
    end
    h[1] = add32(h[1], a)
    h[2] = add32(h[2], b)
    h[3] = add32(h[3], c)
    h[4] = add32(h[4], d)
    h[5] = add32(h[5], e)
    h[6] = add32(h[6], f)
    h[7] = add32(h[7], g)
    h[8] = add32(h[8], hh)
  end

  local out = {}
  for i = 1, 8 do
    local v = h[i]
    out[#out + 1] = math.floor(v / 16777216) % 256
    out[#out + 1] = math.floor(v / 65536) % 256
    out[#out + 1] = math.floor(v / 256) % 256
    out[#out + 1] = v % 256
  end
  return out
end

-- ── HMAC ─────────────────────────────────────────────────────────────────────

local function hmac(hashFn, blockSize, keyBytes, msg)
  if #keyBytes > blockSize then
    keyBytes = hashFn(bytesToString(keyBytes))
  end
  local ipad = table.create(blockSize)
  local opad = table.create(blockSize)
  for i = 1, blockSize do
    local k = keyBytes[i] or 0
    ipad[i] = bit32.bxor(k, 0x36)
    opad[i] = bit32.bxor(k, 0x5C)
  end
  local inner = hashFn(bytesToString(ipad) .. msg)
  return hashFn(bytesToString(opad) .. bytesToString(inner))
end

-- ── Base32 (RFC 4648) ────────────────────────────────────────────────────────

local B32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
local B32_MAP = {}
for i = 1, #B32_ALPHABET do
  B32_MAP[B32_ALPHABET:sub(i, i)] = i - 1
  B32_MAP[B32_ALPHABET:sub(i, i):lower()] = i - 1
end

local function base32Decode(secret)
  secret = string.gsub(secret, "[%s=]", "")
  local bytes = {}
  local buffer, bits = 0, 0
  for i = 1, #secret do
    local v = B32_MAP[secret:sub(i, i)]
    if v == nil then
      return nil, `invalid base32 character '{secret:sub(i, i)}'`
    end
    buffer = buffer * 32 + v
    bits += 5
    if bits >= 8 then
      bits -= 8
      bytes[#bytes + 1] = math.floor(buffer / 2 ^ bits) % 256
      buffer = buffer % 2 ^ bits
    end
  end
  if #bytes == 0 then
    return nil, "empty secret"
  end
  return bytes
end

-- ── TOTP ─────────────────────────────────────────────────────────────────────

local STEAM_CHARS = "23456789BCDFGHJKMNPQRTVWXY"

local function codeFromBytes(hashBytes, digits)
  local offset = hashBytes[#hashBytes] % 16
  local value = ((hashBytes[offset + 1] % 128) * 16777216)
    + (hashBytes[offset + 2] * 65536)
    + (hashBytes[offset + 3] * 256)
    + hashBytes[offset + 4]
  return string.format("%0" .. tostring(digits) .. "d", value % 10 ^ digits)
end

function M.code(spec, epochSeconds)
  if type(spec) ~= "table" or type(spec.secret) ~= "string" then
    return nil, "no secret"
  end
  if spec.algorithm == "sha512" then
    return nil, "sha512 unsupported locally"
  end
  local keyBytes, err = base32Decode(spec.secret)
  if not keyBytes then
    return nil, err
  end
  local counter = math.floor(epochSeconds / spec.period)
  local msg = u32be(math.floor(counter / 4294967296)) .. u32be(counter)
  local hashBytes
  if spec.algorithm == "sha256" then
    hashBytes = hmac(sha256, 64, keyBytes, msg)
  else
    hashBytes = hmac(sha1, 64, keyBytes, msg)
  end
  if spec.kind == "steam" then
    local offset = hashBytes[#hashBytes] % 16
    local value = ((hashBytes[offset + 1] % 128) * 16777216)
      + (hashBytes[offset + 2] * 65536)
      + (hashBytes[offset + 3] * 256)
      + hashBytes[offset + 4]
    local chars = {}
    for _ = 1, 5 do
      local idx = value % #STEAM_CHARS
      chars[#chars + 1] = STEAM_CHARS:sub(idx + 1, idx + 1)
      value = math.floor(value / #STEAM_CHARS)
    end
    return table.concat(chars)
  end
  return codeFromBytes(hashBytes, spec.digits)
end

function M.remaining(spec, epochSeconds)
  local period = (type(spec) == "table" and spec.period) or 30
  return period - (epochSeconds % period)
end

local function decodeQuery(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Accepts: bare base32 secret, otpauth:// URI, steam:// key.
function M.parse(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil, "empty key"
  end
  local trimmed = string.gsub(raw, "^%s*(.-)%s*$", "%1")
  if trimmed:sub(1, 8) == "steam://" then
    local secret = (string.gsub(trimmed:sub(9), "%s", ""))
    if secret == "" then
      return nil, "invalid steam key"
    end
    return { kind = "steam", secret = secret, period = 30, digits = 5, algorithm = "sha1" }
  end
  if trimmed:find("otpauth:", 1, true) then
    -- Normalize label-less forms: otpauth://totp?secret=x -> otpauth://totp/?secret=x
    local normalized = trimmed:gsub("^(otpauth://[%w]+)%?", "%1/?")
    local queryStart = normalized:find("?", 1, true)
    if not queryStart then
      return nil, "invalid otpauth uri"
    end
    local head = normalized:sub(1, queryStart - 1)
    local query = normalized:sub(queryStart + 1)
    local otpType = head:match("^otpauth://([%w]+)")
    if otpType ~= "totp" and otpType ~= "steam" then
      return nil, "only totp keys are supported"
    end
    local params = {}
    for k, v in query:gmatch("([^&=]+)=([^&]*)") do
      params[k:lower()] = decodeQuery(v)
    end
    if not params.secret or params.secret == "" then
      return nil, "missing secret"
    end
    if otpType == "steam" then
      return { kind = "steam", secret = params.secret, period = 30, digits = 5, algorithm = "sha1" }
    end
    local algorithm = (params.algorithm or "sha1"):lower()
    if algorithm ~= "sha1" and algorithm ~= "sha256" and algorithm ~= "sha512" then
      algorithm = "sha1"
    end
    local period = tonumber(params.period) or 30
    local digits = tonumber(params.digits) or 6
    if period <= 0 then
      period = 30
    end
    if digits < 6 or digits > 10 then
      digits = 6
    end
    return { kind = "totp", secret = params.secret, period = period, digits = digits, algorithm = algorithm }
  end
  local secret = (string.gsub(trimmed, "%s", ""))
  return { kind = "totp", secret = secret, period = 30, digits = 6, algorithm = "sha1" }
end

-- Exposed for tests only.
M._sha1Hex = function(s)
  return toHex(sha1(s))
end
M._sha256Hex = function(s)
  return toHex(sha256(s))
end
M._base32Decode = base32Decode

return M
