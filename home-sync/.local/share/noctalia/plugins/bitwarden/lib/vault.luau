--!nonstrict
-- Vault model helpers shared by the service, launcher and panels.
--
-- Pure data logic (no noctalia.* calls): item sanitizing for the launcher
-- cache, search keys, the Raycast-style field list used in the details view,
-- and value extraction for copy/paste commands (including custom fields).

local M = {}

M.TYPE = { LOGIN = 1, NOTE = 2, CARD = 3, IDENTITY = 4, SSH = 5 }
M.MASK = "••••••••"

local TYPE_GLYPHS = {
  [M.TYPE.LOGIN] = "key",
  [M.TYPE.NOTE] = "notes",
  [M.TYPE.CARD] = "credit-card",
  [M.TYPE.IDENTITY] = "id",
  [M.TYPE.SSH] = "ssh",
}

local TYPE_LABEL_KEYS = {
  [M.TYPE.LOGIN] = "type.login",
  [M.TYPE.NOTE] = "type.note",
  [M.TYPE.CARD] = "type.card",
  [M.TYPE.IDENTITY] = "type.identity",
  [M.TYPE.SSH] = "type.ssh",
}

local IDENTITY_KEYS = {
  "title", "firstName", "middleName", "lastName", "username", "company",
  "ssn", "passportNumber", "licenseNumber", "email", "phone",
  "address1", "address2", "address3", "city", "state", "postalCode", "country",
}

local IDENTITY_LABEL_KEYS = {
  title = "fields.identity.title",
  firstName = "fields.identity.firstName",
  middleName = "fields.identity.middleName",
  lastName = "fields.identity.lastName",
  username = "fields.identity.username",
  company = "fields.identity.company",
  ssn = "fields.identity.ssn",
  passportNumber = "fields.identity.passportNumber",
  licenseNumber = "fields.identity.licenseNumber",
  email = "fields.identity.email",
  phone = "fields.identity.phone",
  address1 = "fields.identity.address1",
  address2 = "fields.identity.address2",
  address3 = "fields.identity.address3",
  city = "fields.identity.city",
  state = "fields.identity.state",
  postalCode = "fields.identity.postalCode",
  country = "fields.identity.country",
}

local CARD_KEYS = { "cardholderName", "brand", "number", "expMonth", "expYear", "code" }
local CARD_LABEL_KEYS = {
  cardholderName = "fields.card.cardholderName",
  brand = "fields.card.brand",
  number = "fields.card.number",
  expMonth = "fields.card.expMonth",
  expYear = "fields.card.expYear",
  code = "fields.card.code",
}

local SENSITIVE_CARD_KEYS = { number = true, code = true }
local SENSITIVE_IDENTITY_KEYS = { ssn = true }

function M.glyph(itemType)
  return TYPE_GLYPHS[itemType] or "lock"
end

function M.typeLabelKey(itemType)
  return TYPE_LABEL_KEYS[itemType] or "type.item"
end

local function isString(v)
  return type(v) == "string" and v ~= ""
end

-- Strips secrets; everything the launcher lists/searches without unlocking an
-- extra `bw get item` call.
function M.sanitize(item)
  if type(item) ~= "table" or not isString(item.id) then
    return nil
  end
  local login = type(item.login) == "table" and item.login or nil
  local card = type(item.card) == "table" and item.card or nil
  local identity = type(item.identity) == "table" and item.identity or nil
  local uris = {}
  if login and type(login.uris) == "table" then
    for _, u in ipairs(login.uris) do
      if type(u) == "table" and isString(u.uri) then
        table.insert(uris, u.uri)
      end
    end
  end
  local custom = false
  if type(item.fields) == "table" then
    for _, f in ipairs(item.fields) do
      if type(f) == "table" and type(f.name) == "string" and f.name ~= "" then
        custom = true
        break
      end
    end
  end
  return {
    id = item.id,
    name = isString(item.name) and item.name or "(unnamed)",
    type = type(item.type) == "number" and item.type or M.TYPE.LOGIN,
    folderId = isString(item.folderId) and item.folderId or nil,
    fav = item.favorite == true,
    reprompt = item.reprompt == 1,
    username = login and isString(login.username) and login.username or nil,
    uris = uris,
    brand = card and isString(card.brand) and card.brand or nil,
    email = identity and isString(identity.email) and identity.email or nil,
    hasPassword = login ~= nil and isString(login.password),
    hasTotp = login ~= nil and isString(login.totp),
    hasNotes = isString(item.notes),
    hasUris = #uris > 0,
    custom = custom,
  }
end

-- Strings a query may match against (no holes: nil values break ipairs).
function M.searchKeys(s, folderName)
  local keys = { s.name }
  if isString(s.username) then
    table.insert(keys, s.username)
  end
  if isString(s.brand) then
    table.insert(keys, s.brand)
  end
  if isString(s.email) then
    table.insert(keys, s.email)
  end
  table.insert(keys, M.typeLabelKey(s.type))
  if isString(folderName) then
    table.insert(keys, folderName)
  end
  for _, uri in ipairs(s.uris or {}) do
    table.insert(keys, uri)
    table.insert(keys, M.hostOf(uri))
  end
  return keys
end

function M.hostOf(uri)
  local host = uri:match("^%a+://([^/]+)") or uri
  return (host:gsub("^www%.", ""))
end

-- ── Field list (details view) ────────────────────────────────────────────────

-- Returns an ordered flat list of
--   { path, label_key | label, kind = "text|hidden|link|totp|multiline|bool",
--     value, sensitive }
-- mirroring the Raycast ItemFieldList sections.
function M.fieldList(item)
  local fields = {}
  local function push(path, label_key, kind, value, sensitive, label)
    if not isString(value) then
      return
    end
    table.insert(fields, {
      path = path,
      label_key = label_key,
      label = label,
      kind = kind,
      value = value,
      sensitive = sensitive == true,
    })
  end

  local itemType = item.type
  if itemType == M.TYPE.LOGIN then
    local login = item.login or {}
    push("login.password", "fields.password", "hidden", login.password, true)
    push("login.username", "fields.username", "text", login.username, false)
    push("login.totp.code", "fields.totp", "totp", login.totp, true)
    if type(login.uris) == "table" then
      local n = 0
      for _, u in ipairs(login.uris) do
        if type(u) == "table" and isString(u.uri) then
          n += 1
          push("login.uri." .. tostring(n), "fields.uri", "link", u.uri, false)
        end
      end
    end
  elseif itemType == M.TYPE.CARD then
    local card = item.card or {}
    for _, key in ipairs(CARD_KEYS) do
      push("card." .. key, CARD_LABEL_KEYS[key], key == "number" and "hidden" or "text", card[key], SENSITIVE_CARD_KEYS[key] == true)
    end
  elseif itemType == M.TYPE.IDENTITY then
    local identity = item.identity or {}
    for _, key in ipairs(IDENTITY_KEYS) do
      push("identity." .. key, IDENTITY_LABEL_KEYS[key], key == "ssn" and "hidden" or "text", identity[key], SENSITIVE_IDENTITY_KEYS[key] == true)
    end
  elseif itemType == M.TYPE.SSH then
    local ssh = item.sshKey or {}
    push("ssh.publicKey", "fields.ssh.publicKey", "text", ssh.publicKey, false)
    push("ssh.keyFingerprint", "fields.ssh.keyFingerprint", "text", ssh.keyFingerprint, false)
    push("ssh.privateKey", "fields.ssh.privateKey", "hidden", ssh.privateKey, true)
  end

  push("notes", "fields.notes", "multiline", item.notes, false)

  if type(item.fields) == "table" then
    for i, f in ipairs(item.fields) do
      if type(f) == "table" and f.type ~= 3 then
        local value = f.value
        if f.type == 2 then
          value = value == "true" and "true" or "false"
        end
        if isString(value) then
          table.insert(fields, {
            path = "custom." .. tostring(i),
            label = isString(f.name) and f.name or "Custom field",
            kind = f.type == 1 and "hidden" or (f.type == 2 and "bool" or "text"),
            value = value,
            sensitive = f.type == 1,
          })
        end
      end
    end
  end

  return fields
end

-- Resolves a field path against a full (unsanitized) item.
-- Returns value, sensitive. `login.totp.code` is handled by the service
-- (it needs TOTP computation); everything else is a plain extraction.
function M.extract(item, path)
  if type(item) ~= "table" or type(path) ~= "string" then
    return nil, false
  end
  if path == "notes" then
    return item.notes, false
  end
  if path == "login.password" then
    return item.login and item.login.password, true
  end
  if path == "login.username" then
    return item.login and item.login.username, false
  end
  if path == "login.totp.secret" then
    return item.login and item.login.totp, true
  end
  local uriIndex = path:match("^login%.uri%.(%d+)$")
  if uriIndex then
    local n = 0
    for _, u in ipairs((item.login and item.login.uris) or {}) do
      if type(u) == "table" and isString(u.uri) then
        n += 1
        if n == tonumber(uriIndex) then
          return u.uri, false
        end
      end
    end
    return nil, false
  end
  local cardKey = path:match("^card%.(%a+)$")
  if cardKey then
    return item.card and item.card[cardKey], SENSITIVE_CARD_KEYS[cardKey] == true
  end
  local identityKey = path:match("^identity%.(%a+)$")
  if identityKey then
    return item.identity and item.identity[identityKey], SENSITIVE_IDENTITY_KEYS[identityKey] == true
  end
  local sshKey = path:match("^ssh%.(%a+)$")
  if sshKey then
    return item.sshKey and item.sshKey[sshKey], sshKey == "privateKey"
  end
  local customIndex = path:match("^custom%.(%d+)$")
  if customIndex then
    local f = (item.fields or {})[tonumber(customIndex)]
    if type(f) ~= "table" then
      return nil, false
    end
    local value = f.value
    if f.type == 2 then
      value = value == "true" and "Yes" or "No"
    end
    return value, f.type == 1
  end
  return nil, false
end

function M.basename(path)
  return (path:gsub("/+$", "")):match("([^/]+)$") or path
end

return M
