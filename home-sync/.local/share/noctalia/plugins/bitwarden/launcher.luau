--!nonstrict
-- gery/bitwarden — launcher provider (prefix `/bw`).
--
-- Mirrors the Raycast Bitwarden extension surface inside the launcher:
--
--   /bw              vault search + root actions (items are listed directly)
--   /bw <query>      fuzzy vault search (name, username, URIs, folder, type…)
--   /bw item:<id>    per-item action list (copy/paste password, TOTP, …)
--   /bw details:<id> every field of the item; Enter copies it
--   /bw auth         authenticator: live TOTP codes for items with a key
--   /bw gen          generated password with regenerate/copy/paste
--   /bw sends        Sends list + per-send actions (edit/delete/receive…)
--
-- All subprocess work goes through the service (lib/rpc.luau); this entry
-- only reads `noctalia.state` and renders result rows.

local cfg = require("./lib/cfg.luau")
local rpc = require("./lib/rpc.luau")
local totp = require("./lib/totp.luau")
local vault = require("./lib/vault.luau")

rpc.init()
noctalia.setUpdateInterval(1000)

local RESULT_LIMIT = 60
local SEND_CACHE_MS = 15000
local FRESH_REQUEST_MS = 30000

local currentQuery = nil
local view = "root"
local viewArg = nil

local statusCache = noctalia.state.get("status") or {}
local vaultCache = noctalia.state.get("vault") or {}

local fullItems = {} -- id -> { item, syncedAt, pending }
local totpSecrets = nil
local totpSecretsSyncedAt = -1
local totpPending = false
local sendsCache = nil
local sendsError = nil
local sendsAt = 0
local sendsPending = false
local genValue = nil
local genPending = false
local genError = nil
local lastSecond = -1
local lastFreshMs = 0

local paint -- forward

-- ── small helpers ────────────────────────────────────────────────────────────

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function folderMap()
  local map = {}
  for _, f in ipairs(vaultCache.folders or {}) do
    if type(f) == "table" and type(f.id) == "string" then
      map[f.id] = f.name
    end
  end
  return map
end

local function favoriteSet()
  return vaultCache.favorites or {}
end

local function findItem(id)
  for _, s in ipairs(vaultCache.items or {}) do
    if s.id == id then
      return s
    end
  end
  return nil
end

local function labelOf(field)
  if field.label_key ~= nil then
    return tr(field.label_key)
  end
  return field.label or tr("fields.value")
end

local function itemSubtitle(s, folderName)
  local parts = {}
  if s.username ~= nil then
    table.insert(parts, s.username)
  end
  if s.hasUris then
    table.insert(parts, vault.hostOf(s.uris[1]))
  end
  if s.type == vault.TYPE.CARD and s.brand ~= nil then
    table.insert(parts, s.brand)
  end
  if s.type == vault.TYPE.IDENTITY and s.email ~= nil then
    table.insert(parts, s.email)
  end
  if #parts == 0 then
    if s.type == vault.TYPE.NOTE then
      table.insert(parts, tr("type.note"))
    elseif s.type == vault.TYPE.SSH then
      table.insert(parts, tr("type.ssh"))
    end
  end
  if folderName ~= nil then
    table.insert(parts, 1, "#" .. folderName)
  end
  return table.concat(parts, " · ")
end

local function itemRow(s, folders)
  local title = s.name
  if favoriteSet()[s.id] == true then
    title = "★ " .. title
  end
  return {
    id = "item:" .. s.id,
    title = title,
    subtitle = itemSubtitle(s, folders[s.folderId]),
    glyph = vault.glyph(s.type),
  }
end

-- ── full item cache ──────────────────────────────────────────────────────────

local ensureFullItem -- forward

local function openViewer(id, item)
  local s = findItem(id)
  local title = s ~= nil and s.name or item.name or tr("fields.notes")
  noctalia.state.set("viewer", {
    title = title,
    body = item.notes or "",
    label = tr("fields.notes"),
    sensitive = false,
  })
  noctalia.togglePanel("gery/bitwarden:viewer")
end

ensureFullItem = function(id)
  local synced = vaultCache.syncedAt or 0
  local entry = fullItems[id]
  if entry ~= nil and entry.item ~= nil and entry.syncedAt == synced then
    return entry.item
  end
  if entry ~= nil and entry.pending then
    return nil
  end
  fullItems[id] = { pending = true, syncedAt = synced }
  rpc.send("get-item", { id = id }, function(ok, data, err)
    if ok then
      fullItems[id] = { item = data, syncedAt = synced }
    else
      fullItems[id] = { error = err, syncedAt = synced }
    end
    paint()
  end)
  return nil
end

-- ── row builders ─────────────────────────────────────────────────────────────

local function rootRows()
  local rows = {}
  local state = statusCache.state
  if state == nil then
    table.insert(rows, { id = "", title = tr("root.working"), glyph = "loader" })
    return rows
  end
  if state == "unavailable" then
    table.insert(rows, {
      id = "",
      title = tr("root.binary-missing"),
      subtitle = tr("root.binary-missing-hint"),
      glyph = "alert-triangle",
    })
    table.insert(rows, { id = "root:retry", title = tr("root.retry"), glyph = "refresh" })
    return rows
  end
  if state == "unauthenticated" then
    table.insert(rows, { id = "root:login", title = tr("root.login"), subtitle = tr("root.login-hint"), glyph = "login" })
    table.insert(rows, { id = "root:retry", title = tr("root.retry"), glyph = "refresh" })
    return rows
  end
  if state == "locked" then
    table.insert(rows, { id = "root:unlock", title = tr("root.unlock"), subtitle = tr("root.unlock-hint"), glyph = "lock-open" })
    table.insert(rows, { id = "root:logout", title = tr("root.logout"), glyph = "logout" })
    return rows
  end

  table.insert(rows, { id = "root:gen", title = tr("root.generate"), subtitle = tr("root.generate-hint"), glyph = "wand" })
  table.insert(rows, { id = "root:gen-pass", title = tr("root.generate-passphrase"), glyph = "abc" })
  table.insert(rows, { id = "root:gen-panel", title = tr("root.generator"), subtitle = tr("root.generator-hint"), glyph = "adjustments" })
  table.insert(rows, { id = "root:new-login", title = tr("root.new-login"), glyph = "user-plus" })
  table.insert(rows, { id = "root:new-folder", title = tr("root.new-folder"), glyph = "folder-plus" })
  table.insert(rows, { id = "root:new-send", title = tr("root.new-send"), glyph = "send" })
  table.insert(rows, { id = "root:receive", title = tr("root.receive-send"), glyph = "download" })
  table.insert(rows, { id = "root:auth", title = tr("root.authenticator"), subtitle = tr("root.authenticator-hint"), glyph = "clock" })
  table.insert(rows, { id = "root:sends", title = tr("root.sends"), glyph = "send" })
  table.insert(rows, { id = "root:sync", title = tr("root.sync"), glyph = "refresh" })
  table.insert(rows, { id = "root:lock", title = tr("root.lock"), glyph = "lock" })
  table.insert(rows, { id = "root:logout", title = tr("root.logout"), glyph = "logout" })

  if (statusCache.busy == true) then
    table.insert(rows, { id = "", title = tr("root.working"), glyph = "loader" })
  end

  local folders = folderMap()
  local favorites, others = {}, {}
  for _, s in ipairs(vaultCache.items or {}) do
    if favoriteSet()[s.id] == true then
      table.insert(favorites, s)
    else
      table.insert(others, s)
    end
  end
  local function byName(a, b)
    return a.name:lower() < b.name:lower()
  end
  table.sort(favorites, byName)
  table.sort(others, byName)
  local count = 0
  for _, s in ipairs(favorites) do
    if count >= RESULT_LIMIT then
      break
    end
    table.insert(rows, itemRow(s, folders))
    count += 1
  end
  for _, s in ipairs(others) do
    if count >= RESULT_LIMIT then
      break
    end
    table.insert(rows, itemRow(s, folders))
    count += 1
  end
  if count == 0 and statusCache.state == "unlocked" then
    table.insert(rows, { id = "", title = tr("root.vault-empty"), glyph = "database-off" })
  end
  return rows
end

local function matchScore(s, terms, folderName)
  local keys = vault.searchKeys(s, folderName)
  local total = 0
  for _, term in ipairs(terms) do
    local best = nil
    for _, key in ipairs(keys) do
      local score = noctalia.fuzzyScore(term, key)
      if score ~= nil and (best == nil or score > best) then
        best = score
      end
    end
    if best == nil then
      return nil
    end
    total += best
  end
  return total
end

local function searchRows(text)
  local folders = folderMap()
  local terms = {}
  for term in text:gmatch("%S+") do
    table.insert(terms, term)
  end
  local scored = {}
  for _, s in ipairs(vaultCache.items or {}) do
    local score = matchScore(s, terms, folders[s.folderId])
    if score ~= nil then
      table.insert(scored, { s = s, score = score })
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.s.name:lower() < b.s.name:lower()
  end)
  local rows = {}
  for i, entry in ipairs(scored) do
    if i > RESULT_LIMIT then
      break
    end
    table.insert(rows, itemRow(entry.s, folders))
  end
  if #rows == 0 then
    table.insert(rows, { id = "", title = tr("search.no-matches"), subtitle = tr("search.no-matches-hint"), glyph = "search-off" })
  end
  return rows
end

local PASTEABLE = {
  ["login.password"] = true,
  ["login.username"] = true,
  ["login.totp.code"] = true,
}

local function isPasteable(path)
  return PASTEABLE[path] == true or path:sub(1, 7) == "custom."
end

local FIELD_PRIORITY = {
  ["login.totp.code"] = 1,
  ["login.username"] = 2,
  ["notes"] = 8,
}
local function fieldPriority(path)
  if path:sub(1, 10) == "login.uri." then
    return 3
  end
  if path:sub(1, 7) == "custom." then
    return 7
  end
  return FIELD_PRIORITY[path] or 4
end

local function repromptGuarded(s, intent, description)
  if s.reprompt == true and cfg.bool("respect_reprompt", true) then
    rpc.notify("begin-reprompt", { intent = intent, description = description })
  else
    rpc.notify(intent.action, intent)
  end
end

-- Human-readable label for a field path (notification text); falls back to
-- the path when the item is not cached.
local function fieldLabelFor(id, path)
  local entry = fullItems[id]
  local item = entry ~= nil and entry.item or nil
  if item == nil then
    item = ensureFullItem(id)
  end
  if item == nil then
    return path
  end
  for _, f in ipairs(vault.fieldList(item)) do
    if f.path == path then
      return labelOf(f)
    end
  end
  return path
end

local function itemActionRows(s)
  local id = s.id
  local name = s.name
  local rows = {}
  local item = ensureFullItem(id)
  if item == nil then
    table.insert(rows, { id = "", title = tr("item.loading"), glyph = "loader" })
    return rows
  end

  local primary = cfg.str("primary_action", "show_details")
  local detailsRow = { id = "a|details|" .. id, title = tr("actions.show-details"), glyph = "list" }

  local fields = vault.fieldList(item)
  local loginPasswordRow = nil
  for _, f in ipairs(fields) do
    if f.path == "login.password" then
      loginPasswordRow = f
    end
  end

  local function addFieldPair(f)
    local copyId = "a|copy|" .. id .. "|" .. f.path
    local pasteId = "a|paste|" .. id .. "|" .. f.path
    local label = labelOf(f)
    local title = tr("actions.copy-field", { field = label })
    table.insert(rows, {
      id = copyId,
      title = title,
      subtitle = f.kind == "hidden" and vault.MASK or nil,
      glyph = f.kind == "totp" and "clock" or "copy",
    })
    if isPasteable(f.path) then
      local pasteTitle = tr("actions.paste-field", { field = label })
      table.insert(rows, { id = pasteId, title = pasteTitle, glyph = "clipboard-text" })
    end
  end

  -- Primary trio (details / copy password / paste password) in Raycast's
  -- ComponentOrderer order: the configured primary action first, the other
  -- two following the component order (copy before paste).
  local trio
  if loginPasswordRow ~= nil then
    local label = labelOf(loginPasswordRow)
    local copyRow = {
      id = "a|copy|" .. id .. "|login.password",
      title = tr("actions.copy-field", { field = label }),
      subtitle = vault.MASK,
      glyph = "copy",
    }
    local pasteRow = {
      id = "a|paste|" .. id .. "|login.password",
      title = tr("actions.paste-field", { field = label }),
      glyph = "clipboard-text",
    }
    if primary == "copy_password" then
      trio = { copyRow, detailsRow, pasteRow }
    elseif primary == "paste_password" then
      trio = { pasteRow, detailsRow, copyRow }
    else
      trio = { detailsRow, copyRow, pasteRow }
    end
  else
    trio = { detailsRow }
  end
  for i = #trio, 1, -1 do
    table.insert(rows, 1, trio[i])
  end

  -- remaining fields in Raycast-ish order
  local sortedFields = {}
  for i, f in ipairs(fields) do
    if f.path ~= "login.password" then
      table.insert(sortedFields, { f = f, i = i })
    end
  end
  table.sort(sortedFields, function(a, b)
    local pa, pb = fieldPriority(a.f.path), fieldPriority(b.f.path)
    if pa ~= pb then
      return pa < pb
    end
    return a.i < b.i
  end)
  for _, entry in ipairs(sortedFields) do
    addFieldPair(entry.f)
  end

  -- open in browser + notes viewer
  if item.login ~= nil and type(item.login.uris) == "table" then
    for _, u in ipairs(item.login.uris) do
      if type(u) == "table" and type(u.uri) == "string" and u.uri ~= "" then
        table.insert(rows, {
          id = "a|openurl|" .. id .. "|" .. u.uri,
          title = tr("actions.open-in-browser", { host = vault.hostOf(u.uri) }),
          glyph = "external-link",
        })
        break
      end
    end
  end
  if type(item.notes) == "string" and item.notes ~= "" then
    table.insert(rows, { id = "a|notes|" .. id, title = tr("actions.show-notes"), glyph = "notes" })
  end

  local favorite = favoriteSet()[id] == true
  table.insert(rows, {
    id = "a|fav|" .. id,
    title = favorite and tr("actions.unfavorite") or tr("actions.favorite"),
    glyph = favorite and "star-filled" or "star",
  })

  table.insert(rows, { id = "a|vault|sync", title = tr("root.sync"), glyph = "refresh" })
  table.insert(rows, { id = "a|vault|lock", title = tr("root.lock"), glyph = "lock" })
  table.insert(rows, { id = "a|vault|logout", title = tr("root.logout"), glyph = "logout" })
  table.insert(rows, { id = "a|back", title = tr("actions.back"), glyph = "arrow-left" })
  return rows
end

local function fieldSubtitle(f, item)
  if f.kind == "totp" then
    local login = item.login
    local raw = login and login.totp
    if type(raw) == "string" and raw ~= "" then
      local spec = totp.parse(raw)
      if spec then
        local code = totp.code(spec, os.time())
        if code then
          return code .. " · " .. tostring(totp.remaining(spec, os.time())) .. "s"
        end
      end
    end
    return tr("auth.unavailable")
  end
  if f.kind == "hidden" then
    return vault.MASK
  end
  local value = f.value or ""
  value = value:gsub("\n", " ")
  if #value > 90 then
    value = value:sub(1, 89) .. "…"
  end
  return value
end

local function detailsRows(id)
  local rows = {}
  local s = findItem(id)
  local item = ensureFullItem(id)
  if item == nil then
    table.insert(rows, { id = "", title = tr("item.loading"), subtitle = s ~= nil and s.name or nil, glyph = "loader" })
    return rows
  end
  local fields = vault.fieldList(item)
  for _, f in ipairs(fields) do
    table.insert(rows, {
      id = "a|copy|" .. id .. "|" .. f.path,
      title = labelOf(f),
      subtitle = fieldSubtitle(f, item),
      glyph = f.kind == "totp" and "clock" or (f.kind == "link" and "link" or (f.kind == "multiline" and "notes" or "copy")),
    })
  end
  if #fields == 0 then
    table.insert(rows, { id = "", title = tr("item.no-fields"), glyph = "mood-empty" })
  end
  table.insert(rows, { id = "a|item|" .. id, title = tr("actions.back-actions"), glyph = "arrow-left" })
  return rows
end

local function ensureTotpSecrets()
  local synced = vaultCache.syncedAt or 0
  if totpSecrets ~= nil and totpSecretsSyncedAt == synced then
    return
  end
  if totpPending then
    return
  end
  totpPending = true
  rpc.send("totp-secrets", nil, function(ok, data)
    totpPending = false
    if ok and type(data) == "table" then
      totpSecrets = data
      totpSecretsSyncedAt = synced
    end
    paint()
  end)
end

local function authRows(filter)
  ensureTotpSecrets()
  local rows = {}
  local secrets = totpSecrets
  if secrets == nil then
    table.insert(rows, { id = "", title = tr("auth.loading"), glyph = "loader" })
    return rows
  end
  local folders = folderMap()
  local terms = {}
  for term in (filter or ""):gmatch("%S+") do
    table.insert(terms, term)
  end
  local list = {}
  for _, s in ipairs(vaultCache.items or {}) do
    if s.hasTotp then
      local include = #terms == 0
      if not include then
        include = matchScore(s, terms, folders[s.folderId]) ~= nil
      end
      if include then
        table.insert(list, s)
      end
    end
  end
  table.sort(list, function(a, b)
    local fa = favoriteSet()[a.id] == true
    local fb = favoriteSet()[b.id] == true
    if fa ~= fb then
      return fa
    end
    return a.name:lower() < b.name:lower()
  end)
  if #list == 0 then
    table.insert(rows, { id = "", title = tr("auth.empty"), subtitle = tr("auth.empty-hint"), glyph = "clock-off" })
    return rows
  end
  local now = os.time()
  for i, s in ipairs(list) do
    if i > RESULT_LIMIT then
      break
    end
    local subtitle
    if s.reprompt == true and cfg.bool("respect_reprompt", true) then
      subtitle = tr("auth.needs-confirm")
    else
      local raw = secrets[s.id]
      local spec = type(raw) == "string" and raw ~= "" and totp.parse(raw) or nil
      local code = spec and totp.code(spec, now) or nil
      if code ~= nil then
        subtitle = code .. " · " .. tostring(totp.remaining(spec, now)) .. "s"
      else
        subtitle = tr("auth.unavailable")
      end
    end
    table.insert(rows, {
      id = "auth:" .. s.id,
      title = favoriteSet()[s.id] == true and ("★ " .. s.name) or s.name,
      subtitle = subtitle,
      glyph = "clock",
    })
  end
  return rows
end

local function authCodeRows(id)
  local s = findItem(id)
  if s == nil then
    return { { id = "", title = tr("item.missing"), glyph = "alert-triangle" } }
  end
  local rows = {}
  local guarded = s.reprompt == true and cfg.bool("respect_reprompt", true)
  local description = tr("reprompt.action", { action = tr("fields.totp"), item = s.name })
  if guarded then
    table.insert(rows, {
      id = "a|confirm-totp|" .. id,
      title = tr("auth.confirm"),
      subtitle = tr("auth.confirm-hint"),
      glyph = "lock",
    })
  end
  table.insert(rows, {
    id = "a|copy|" .. id .. "|login.totp.code",
    title = tr("actions.copy-field", { field = tr("fields.totp") }),
    subtitle = guarded and nil or tr("auth.copy-hint"),
    glyph = "copy",
  })
  table.insert(rows, {
    id = "a|paste|" .. id .. "|login.totp.code",
    title = tr("actions.paste-field", { field = tr("fields.totp") }),
    glyph = "clipboard-text",
  })
  table.insert(rows, { id = "a|auth-back", title = tr("actions.back"), glyph = "arrow-left" })
  return rows
end

local function genRows()
  if genValue == nil and not genPending and genError == nil then
    genPending = true
    rpc.send("generate", nil, function(ok, data, err)
      genPending = false
      if ok and type(data) == "table" then
        genValue = data.value
      else
        genValue = nil
        genError = err or tr("gen.failed")
      end
      paint()
    end)
  end
  local rows = {}
  if genValue ~= nil then
    table.insert(rows, {
      id = "gen:value",
      title = genValue,
      subtitle = tr("gen.press-to-copy"),
      glyph = "wand",
    })
  elseif genPending then
    table.insert(rows, { id = "", title = tr("gen.generating"), glyph = "loader" })
  else
    table.insert(rows, { id = "", title = tr("gen.failed"), subtitle = genError, glyph = "alert-triangle" })
  end
  table.insert(rows, { id = "gen:regen", title = tr("gen.regenerate"), glyph = "refresh" })
  table.insert(rows, { id = "gen:panel", title = tr("root.generator"), subtitle = tr("root.generator-hint"), glyph = "adjustments" })
  return rows
end

local function ensureSends(force)
  local now = noctalia.nowMs()
  if not force and sendsCache ~= nil and now - sendsAt < SEND_CACHE_MS then
    return
  end
  if sendsPending then
    return
  end
  sendsPending = true
  rpc.send("send-list", nil, function(ok, data, err)
    sendsPending = false
    if ok and type(data) == "table" then
      sendsCache = data.sends or {}
      sendsError = nil
    else
      sendsError = err
    end
    -- throttle retries after failures too
    sendsAt = noctalia.nowMs()
    paint()
  end)
end

local function sendSubtitle(send)
  local parts = {}
  table.insert(parts, send.type == 1 and tr("sends.file") or tr("sends.text"))
  if send.passwordSet then
    table.insert(parts, tr("sends.password"))
  end
  if send.disabled then
    table.insert(parts, tr("sends.disabled"))
  end
  if type(send.expirationDate) == "string" and send.expirationDate ~= "" then
    table.insert(parts, tr("sends.expires", { date = send.expirationDate:sub(1, 10) }))
  end
  if send.maxAccessCount ~= nil then
    table.insert(parts, tostring(send.accessCount) .. "/" .. tostring(send.maxAccessCount))
  end
  return table.concat(parts, " · ")
end

local function sendsRows(filter)
  ensureSends(false)
  local rows = {}
  table.insert(rows, { id = "root:new-send", title = tr("root.new-send"), glyph = "send" })
  table.insert(rows, { id = "root:receive", title = tr("root.receive-send"), glyph = "download" })
  if sendsCache == nil then
    table.insert(rows, { id = "", title = sendsPending and tr("sends.loading") or tr("sends.failed"), subtitle = sendsError, glyph = "loader" })
    return rows
  end
  table.insert(rows, {
    id = "sends:refresh",
    title = tr("sends.refresh"),
    glyph = "refresh",
  })
  local terms = {}
  for term in (filter or ""):gmatch("%S+") do
    table.insert(terms, term)
  end
  local shown = 0
  for _, send in ipairs(sendsCache) do
    local include = #terms == 0
    if not include and send.name ~= nil then
      include = matchScore({ name = send.name, uris = { send.accessUrl or "" }, type = vault.TYPE.NOTE }, terms, nil) ~= nil
    end
    if include then
      shown += 1
      if shown <= RESULT_LIMIT then
        table.insert(rows, {
          id = "send:" .. send.id,
          title = send.disabled and ("⏸ " .. send.name) or send.name,
          subtitle = sendSubtitle(send),
          glyph = "send",
        })
      end
    end
  end
  if shown == 0 then
    table.insert(rows, { id = "", title = tr("sends.empty"), subtitle = tr("sends.empty-hint"), glyph = "send-off" })
  end
  return rows
end

local function sendActionRows(id)
  local rows = {}
  local send = nil
  for _, s in ipairs(sendsCache or {}) do
    if s.id == id then
      send = s
      break
    end
  end
  if send == nil then
    return { { id = "", title = tr("sends.missing"), glyph = "alert-triangle" } }
  end
  table.insert(rows, { id = "a|back-sends", title = tr("actions.back"), glyph = "arrow-left" })
  table.insert(rows, { id = "a|send-copy|" .. id, title = tr("sends.copy-link"), glyph = "link" })
  table.insert(rows, { id = "a|send-paste|" .. id, title = tr("sends.paste-link"), glyph = "clipboard-text" })
  table.insert(rows, { id = "a|send-open|" .. id, title = tr("sends.open-browser"), glyph = "external-link" })
  table.insert(rows, { id = "a|send-edit|" .. id, title = tr("sends.edit"), glyph = "edit" })
  if send.passwordSet then
    table.insert(rows, { id = "a|send-removepw|" .. id, title = tr("sends.remove-password"), glyph = "lock-open" })
  end
  table.insert(rows, { id = "a|send-delete|" .. id, title = tr("sends.delete"), glyph = "trash" })
  return rows
end

local function sendDeleteRows(id)
  return {
    { id = "a|send-delete-confirm|" .. id, title = tr("sends.delete-confirm"), subtitle = tr("sends.delete-confirm-hint"), glyph = "trash" },
    { id = "a|send-delete-cancel|" .. id, title = tr("sends.delete-cancel"), glyph = "arrow-left" },
  }
end

-- ── rendering ────────────────────────────────────────────────────────────────

local function requestFresh()
  if statusCache.state ~= "unlocked" then
    return
  end
  local now = noctalia.nowMs()
  if now - lastFreshMs < FRESH_REQUEST_MS then
    return
  end
  lastFreshMs = now
  rpc.notify("ensure-fresh")
end

local function pageRows()
  if view == "root" then
    requestFresh()
    return rootRows()
  elseif view == "search" then
    requestFresh()
    return searchRows(viewArg)
  elseif view == "item" then
    local s = findItem(viewArg)
    if s == nil then
      return { { id = "", title = tr("item.missing"), glyph = "alert-triangle" } }
    end
    return itemActionRows(s)
  elseif view == "details" then
    return detailsRows(viewArg)
  elseif view == "auth" then
    return authRows(viewArg)
  elseif view == "authcode" then
    return authCodeRows(viewArg)
  elseif view == "gen" then
    return genRows()
  elseif view == "sends" then
    return sendsRows(viewArg)
  elseif view == "senda" then
    return sendActionRows(viewArg)
  elseif view == "senddel" then
    return sendDeleteRows(viewArg)
  end
  return {}
end

paint = function()
  if currentQuery == nil then
    return
  end
  launcher.setResults(currentQuery, pageRows())
end

local function parseView(text)
  local t = trim(text)
  if t == "" then
    return "root", nil
  end
  local itemId = t:match("^item:([%w%-]+)$")
  if itemId ~= nil then
    return "item", itemId
  end
  local detailsId = t:match("^details:([%w%-]+)$")
  if detailsId ~= nil then
    return "details", detailsId
  end
  local authcodeId = t:match("^authcode:([%w%-]+)$")
  if authcodeId ~= nil then
    return "authcode", authcodeId
  end
  local sendaId = t:match("^senda:([%w%-]+)$")
  if sendaId ~= nil then
    return "senda", sendaId
  end
  local senddelId = t:match("^senddel:([%w%-]+)$")
  if senddelId ~= nil then
    return "senddel", senddelId
  end
  if t == "auth" then
    return "auth", nil
  end
  if t:match("^auth%s") then
    return "auth", trim(t:sub(6))
  end
  if t == "gen" then
    return "gen", nil
  end
  if t == "sends" then
    return "sends", nil
  end
  if t:match("^sends%s") then
    return "sends", trim(t:sub(7))
  end
  return "search", t
end

function onQuery(text)
  text = text or ""
  currentQuery = text
  local previousView = view
  view, viewArg = parseView(text)
  if view == "gen" and previousView ~= "gen" then
    -- fresh generation each time the generator view is entered
    genValue = nil
    genError = nil
    genPending = false
  end
  paint()
end

-- ── activation ───────────────────────────────────────────────────────────────

local function guardedFieldAction(s, action, path, description)
  repromptGuarded(s, {
    action = action .. "-field",
    id = s.id,
    path = path,
    label = fieldLabelFor(s.id, path),
  }, description)
end

local function activateAction(id)
  local action, a, b = id:match("^a|([%w%-]+)|([^|]+)|(.*)$")
  if action == nil then
    action, a = id:match("^a|([%w%-]+)|(.*)$")
  end
  if action == nil then
    action = id:match("^a|([%w%-]+)$")
  end

  if action == "back" then
    launcher.setQuery("")
    return
  end
  if action == "back-sends" then
    launcher.setQuery("sends ")
    return
  end
  if action == "auth-back" then
    launcher.setQuery("auth ")
    return
  end
  if action == "details" and a ~= nil then
    launcher.setQuery("details:" .. a .. " ")
    return
  end
  if action == "item" and a ~= nil then
    launcher.setQuery("item:" .. a .. " ")
    return
  end
  if action == "fav" and a ~= nil then
    rpc.notify("favorite-toggle", { id = a })
    return
  end
  if action == "vault" and a ~= nil then
    rpc.notify(a)
    return
  end
  if action == "openurl" and a ~= nil and b ~= nil then
    rpc.notify("open-url", { url = b })
    return
  end
  if action == "notes" and a ~= nil then
    local item = ensureFullItem(a)
    if item ~= nil then
      openViewer(a, item)
    else
      rpc.send("get-item", { id = a }, function(ok, data)
        if ok and type(data) == "table" then
          fullItems[a] = { item = data, syncedAt = vaultCache.syncedAt or 0 }
          openViewer(a, data)
          paint()
        end
      end)
    end
    return
  end
  if action == "copy" and a ~= nil and b ~= nil then
    local s = findItem(a)
    if s == nil then
      return
    end
    guardedFieldAction(s, "copy", b, tr("reprompt.action", { action = tr("actions.copy"), item = s.name }))
    return
  end
  if action == "paste" and a ~= nil and b ~= nil then
    local s = findItem(a)
    if s == nil then
      return
    end
    guardedFieldAction(s, "paste", b, tr("reprompt.action", { action = tr("actions.paste"), item = s.name }))
    return
  end
  if action == "confirm-totp" and a ~= nil then
    local s = findItem(a)
    if s == nil then
      return
    end
    rpc.notify("begin-reprompt", {
      intent = { action = "copy-field", id = a, path = "login.totp.code", label = tr("fields.totp") },
      description = tr("reprompt.action", { action = tr("fields.totp"), item = s.name }),
    })
    return
  end
  if action == "send-copy" and a ~= nil then
    local send = nil
    for _, s in ipairs(sendsCache or {}) do
      if s.id == a then
        send = s
        break
      end
    end
    if send ~= nil then
      rpc.notify("copy-value", { value = send.accessUrl, label = tr("fields.send-link") })
    end
    return
  end
  if action == "send-paste" and a ~= nil then
    local send = nil
    for _, s in ipairs(sendsCache or {}) do
      if s.id == a then
        send = s
        break
      end
    end
    if send ~= nil then
      rpc.notify("paste-value", { value = send.accessUrl, label = tr("fields.send-link") })
    end
    return
  end
  if action == "send-open" and a ~= nil then
    local send = nil
    for _, s in ipairs(sendsCache or {}) do
      if s.id == a then
        send = s
        break
      end
    end
    if send ~= nil then
      rpc.notify("open-url", { url = send.accessUrl })
    end
    return
  end
  if action == "send-edit" and a ~= nil then
    noctalia.state.set("send-edit", { id = a })
    noctalia.togglePanel("gery/bitwarden:create-send")
    return
  end
  if action == "send-removepw" and a ~= nil then
    rpc.notify("send-remove-password", { id = a })
    sendsAt = 0
    return
  end
  if action == "send-delete" and a ~= nil then
    launcher.setQuery("senddel:" .. a .. " ")
    return
  end
  if action == "send-delete-confirm" and a ~= nil then
    rpc.notify("send-delete", { id = a })
    sendsAt = 0
    launcher.setQuery("sends ")
    return
  end
  if action == "send-delete-cancel" and a ~= nil then
    launcher.setQuery("senda:" .. a .. " ")
    return
  end
  if action == "gen-copy" then
    if genValue ~= nil then
      rpc.notify("copy-value", { value = genValue, label = tr("notify.generated"), sensitive = true })
    end
    return
  end
end

local function activateRoot(name)
  if name == "gen" then
    rpc.notify("quick-generate", { mode = "password" })
  elseif name == "gen-pass" then
    rpc.notify("quick-generate", { mode = "passphrase" })
  elseif name == "gen-panel" then
    noctalia.togglePanel("gery/bitwarden:generator")
  elseif name == "new-login" or name == "new-folder" or name == "new-send" or name == "receive" then
    if statusCache.state ~= "unlocked" then
      noctalia.togglePanel("gery/bitwarden:auth-unlock")
      return
    end
    if name == "new-login" then
      noctalia.togglePanel("gery/bitwarden:create-login")
    elseif name == "new-folder" then
      noctalia.togglePanel("gery/bitwarden:create-folder")
    elseif name == "new-send" then
      noctalia.state.set("send-edit", nil)
      noctalia.togglePanel("gery/bitwarden:create-send")
    else
      noctalia.togglePanel("gery/bitwarden:receive-send")
    end
  elseif name == "auth" then
    launcher.setQuery("auth ")
  elseif name == "sends" then
    launcher.setQuery("sends ")
  elseif name == "sync" then
    rpc.notify("sync")
  elseif name == "lock" then
    rpc.notify("lock")
  elseif name == "logout" then
    rpc.notify("logout")
  elseif name == "login" then
    noctalia.togglePanel("gery/bitwarden:auth-login")
  elseif name == "unlock" then
    noctalia.togglePanel("gery/bitwarden:auth-unlock")
  elseif name == "retry" then
    rpc.notify("status-poll")
  end
end

function onActivate(id)
  if type(id) ~= "string" or id == "" then
    return
  end
  if id:sub(1, 5) == "root:" then
    activateRoot(id:sub(6))
    return
  end
  local itemId = id:match("^item:(.+)$")
  if itemId ~= nil then
    launcher.setQuery("item:" .. itemId .. " ")
    return
  end
  local authId = id:match("^auth:(.+)$")
  if authId ~= nil then
    launcher.setQuery("authcode:" .. authId .. " ")
    return
  end
  local sendId = id:match("^send:(.+)$")
  if sendId ~= nil then
    launcher.setQuery("senda:" .. sendId .. " ")
    return
  end
  if id == "gen:value" then
    if genValue ~= nil then
      rpc.notify("copy-value", { value = genValue, label = tr("notify.generated"), sensitive = true })
    end
    return
  end
  if id == "gen:regen" then
    genValue = nil
    genError = nil
    genPending = false
    paint()
    return
  end
  if id == "gen:panel" then
    noctalia.togglePanel("gery/bitwarden:generator")
    return
  end
  if id == "sends:refresh" then
    ensureSends(true)
    return
  end
  if id:sub(1, 2) == "a|" then
    activateAction(id)
    return
  end
end

-- ── state watchers / ticks ───────────────────────────────────────────────────

noctalia.state.watch("status", function(value)
  statusCache = value or {}
  paint()
end)

noctalia.state.watch("vault", function(value)
  vaultCache = value or {}
  paint()
end)

function update()
  local second = os.time()
  if second == lastSecond then
    return
  end
  lastSecond = second
  if view == "auth" or view == "authcode" or view == "details" then
    paint()
  end
end
