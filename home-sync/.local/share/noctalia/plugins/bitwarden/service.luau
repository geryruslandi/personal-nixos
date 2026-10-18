--!nonstrict
-- gery/bitwarden — service entry.
--
-- Sole owner of `bw` subprocesses: session (unlock/login/reprompt), vault
-- cache, copy/paste with clipboard clearing, generator, creates, sends and
-- vault actions. Browser VMs (the /bw launcher provider and the panels) talk
-- to it through lib/rpc.luau's command/response channel.

local b64 = require("./lib/b64.luau")
local cfg = require("./lib/cfg.luau")
local totp = require("./lib/totp.luau")
local vault = require("./lib/vault.luau")

noctalia.setUpdateInterval(1000)

local STATUS_POLL_TICKS = 30 -- ~30s
local OP_WATCHDOG_MS = 75000

local status = {
  state = "unavailable", -- unavailable | unauthenticated | locked | unlocked
  email = "",
  serverUrl = "",
  error = "",
  available = false,
}
local token = nil
local items = {}
local folders = {}
local totpSecrets = {}
local favorites = {}
local syncedAt = 0
local queue = {}
local busy = false
local currentCmd = nil
local busyStartedMs = 0
local pendingIntent = nil
local pendingClear = nil -- { value, deadlineMs }
local lockDeadlineMs = nil
local tickCount = 0
local lastEnsureMs = 0
local binPath = nil
local wtypePath = nil
local wtypeChecked = false

-- ── helpers ──────────────────────────────────────────────────────────────────

local function log(msg)
  noctalia.log(`bitwarden: {msg}`)
end

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function clean(s)
  if type(s) ~= "string" then
    return ""
  end
  return (string.gsub(s, "\27%[[%d;]*m", ""))
end

local function trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function expandBinary(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if name:find("/") ~= nil then
    local absolute = noctalia.expandPath(name)
    if noctalia.fileExists(absolute) then
      return absolute
    end
    return nil
  end
  local path = noctalia.getenv("PATH") or ""
  for dir in path:gmatch("[^:]+") do
    local candidate = dir .. "/" .. name
    if noctalia.fileExists(candidate) then
      return candidate
    end
  end
  return nil
end

local function resolveBinary()
  binPath = expandBinary(cfg.str("bw_binary", "bw"))
  status.available = binPath ~= nil
  if not status.available then
    status.state = "unavailable"
    status.error = tr("error.binary-missing")
  elseif status.state == "unavailable" then
    status.state = "locked"
    status.error = ""
  end
end

local function isSensitive(field)
  return field == true
end

-- ── state publishing ─────────────────────────────────────────────────────────

local function publishStatus()
  noctalia.state.set("status", {
    state = status.state,
    email = status.email,
    serverUrl = status.serverUrl,
    error = status.error,
    available = status.available,
    busy = busy,
    binary = binPath or "",
  })
end

local function publishVault()
  noctalia.state.set("vault", {
    items = items,
    folders = folders,
    favorites = favorites,
    syncedAt = syncedAt,
    state = status.state,
    busy = busy,
  })
end

local function setState(state)
  if status.state ~= state then
    status.state = state
  end
  publishStatus()
end

local function clearSessionData()
  token = nil
  items = {}
  folders = {}
  totpSecrets = {}
  syncedAt = 0
  lockDeadlineMs = nil
  pendingIntent = nil
end

local function touchActivity()
  local minutes = cfg.timeoutMinutes()
  if minutes == nil then
    lockDeadlineMs = nil
  else
    lockDeadlineMs = noctalia.nowMs() + minutes * 60000
  end
end

-- ── subprocess plumbing ──────────────────────────────────────────────────────

-- Node >= 20 enables happy-eyeballs (autoSelectFamily). On hosts that have an
-- IPv6 default route but no global IPv6 address (RA with no prefix), the
-- dual-stack connect fails outright ("fetch failed, reason: " with an empty
-- cause) instead of falling back to IPv4 — which breaks every network `bw`
-- command. Disable the family autoselection for bw subprocesses.
local NODE_FIX_FLAG = "--no-network-family-autoselection"

local function bwNodeOptions()
  local existing = noctalia.getenv("NODE_OPTIONS") or ""
  if existing:find(NODE_FIX_FLAG, 1, true) ~= nil then
    return existing
  end
  if existing == "" then
    return NODE_FIX_FLAG
  end
  return existing .. " " .. NODE_FIX_FLAG
end

local function runBw(args, cb, timeoutMs, opts)
  if binPath == nil then
    cb({ ok = false, code = -1, stdout = "", stderr = status.error ~= "" and status.error or tr("error.binary-missing") })
    return
  end
  opts = opts or {}
  local argv = { binPath }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  if opts.session ~= false and token ~= nil then
    table.insert(argv, "--session")
    table.insert(argv, token)
  end
  table.insert(argv, "--nointeraction")

  -- env overrides are always in play (NODE_OPTIONS), so every bw command runs
  -- as a fully quoted shell string
  local env = { NODE_OPTIONS = bwNodeOptions() }
  if opts.env ~= nil then
    for k, v in pairs(opts.env) do
      env[k] = v
    end
  end
  local parts = {}
  local certs = cfg.str("server_certs_path", "")
  if certs ~= "" then
    table.insert(parts, "NODE_EXTRA_CA_CERTS=" .. shellQuote(certs))
  end
  for k, v in pairs(env) do
    table.insert(parts, k .. "=" .. shellQuote(v))
  end
  local quoted = {}
  for _, a in ipairs(argv) do
    table.insert(quoted, shellQuote(a))
  end
  local cmd = table.concat(parts, " ") .. " " .. table.concat(quoted, " ")

  noctalia.runAsync(cmd, function(result)
    if type(result) ~= "table" then
      cb({ ok = false, code = -1, stdout = "", stderr = "no result" })
      return
    end
    cb({
      ok = result.exitCode == 0 and result.timedOut ~= true,
      code = result.exitCode,
      stdout = result.stdout or "",
      stderr = clean(result.stderr),
      timedOut = result.timedOut == true,
    })
  end, timeoutMs or 20000)
end

-- Session-loss detection: token invalidated externally or vault locked.
local function fingerprintFailure(result)
  local text = result.stderr ~= "" and result.stderr or result.stdout
  local lower = string.lower(text)
  if lower:find("vault is locked", 1, true) or lower:find("invalid session token", 1, true) then
    clearSessionData()
    status.state = "locked"
    status.error = ""
    publishStatus()
    publishVault()
  elseif lower:find("not logged in", 1, true) then
    clearSessionData()
    status.state = "unauthenticated"
    status.error = ""
    publishStatus()
    publishVault()
  end
  return trim(text)
end

local function isEmptyOutput(result)
  return trim(result.stdout) == "" and trim(result.stderr) == ""
end

-- ── clipboard / paste ────────────────────────────────────────────────────────

local function doCopy(value, label, sensitive)
  noctalia.copyToClipboard(value, "text/plain;charset=utf-8")
  local seconds = cfg.int("clear_clipboard_seconds", 30, 0, 300)
  if sensitive == true and seconds > 0 then
    pendingClear = { value = value, deadlineMs = noctalia.nowMs() + seconds * 1000 }
  else
    pendingClear = nil
  end
  if cfg.bool("notify_on_copy", true) then
    noctalia.notify(tr("title"), tr("notify.copied", { label = label }))
  end
end

local function pasteToolPath()
  if not wtypeChecked then
    wtypeChecked = true
    wtypePath = expandBinary("wtype")
  end
  return wtypePath
end

local function doPaste(value, label, sensitive, done)
  local wtype = pasteToolPath()
  if wtype == nil or value == "" then
    doCopy(value, label, sensitive)
    noctalia.notify(tr("title"), tr("notify.paste-fallback", { label = label }))
    done()
    return
  end
  local sleepPath = expandBinary("sleep")
  local function typeIt()
    noctalia.runAsync({ wtype, "--", value }, function(result)
      if type(result) == "table" and result.exitCode == 0 and not result.timedOut then
        if cfg.bool("notify_on_copy", true) then
          noctalia.notify(tr("title"), tr("notify.pasted", { label = label }))
        end
      else
        doCopy(value, label, sensitive)
        noctalia.notify(tr("title"), tr("notify.paste-fallback", { label = label }))
      end
      done()
    end, 15000)
  end
  if sleepPath ~= nil then
    noctalia.runAsync({ sleepPath, "0.25" }, function()
      typeIt()
    end, 3000)
  else
    typeIt()
  end
end

-- ── value resolution ─────────────────────────────────────────────────────────

local function fetchItem(id, cb)
  if status.state ~= "unlocked" or token == nil then
    cb(false, nil, tr("error.vault-locked"))
    return
  end
  runBw({ "get", "item", id }, function(result)
    if not result.ok then
      cb(false, nil, fingerprintFailure(result))
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      cb(false, nil, tr("error.invalid-response"))
      return
    end
    cb(true, decoded)
  end, 20000)
end

local function totpCodeFor(item, id, cb)
  local raw = item.login and item.login.totp
  if type(raw) == "string" and raw ~= "" then
    local spec = totp.parse(raw)
    if spec then
      local code = totp.code(spec, os.time())
      if code then
        cb(true, code)
        return
      end
    end
  end
  -- sha512 or unparseable: let the CLI compute it
  runBw({ "get", "totp", id }, function(result)
    if result.ok and trim(result.stdout) ~= "" then
      cb(true, trim(result.stdout))
    else
      cb(false, nil, fingerprintFailure(result))
    end
  end, 20000)
end

-- cb(ok, value, sensitive, error)
local function resolveValue(id, path, cb)
  if path == "login.totp.code" then
    fetchItem(id, function(ok, item, err)
      if not ok then
        cb(false, nil, true, err)
        return
      end
      totpCodeFor(item, id, function(codeOk, code, codeErr)
        cb(codeOk, code, true, codeErr)
      end)
    end)
    return
  end
  fetchItem(id, function(ok, item, err)
    if not ok then
      cb(false, nil, false, err)
      return
    end
    local value, sensitive = vault.extract(item, path)
    if type(value) ~= "string" or value == "" then
      cb(false, nil, sensitive == true, tr("error.field-empty"))
      return
    end
    cb(true, value, sensitive == true)
  end)
end

-- ── vault refresh ────────────────────────────────────────────────────────────

local function persistFavorites()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" then
    return
  end
  local list = {}
  for id in pairs(favorites) do
    table.insert(list, id)
  end
  noctalia.writeFile(dir .. "/favorites.json", noctalia.json.encode(list) or "[]")
end

local function loadFavorites()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" then
    return
  end
  local raw = noctalia.readFile(dir .. "/favorites.json")
  if type(raw) ~= "string" then
    return
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) == "table" then
    favorites = {}
    for _, id in ipairs(decoded) do
      if type(id) == "string" then
        favorites[id] = true
      end
    end
  end
end

local function refreshVault(cb)
  if token == nil then
    cb(false, tr("error.vault-locked"))
    return
  end
  runBw({ "list", "items" }, function(result)
    if not result.ok then
      cb(false, fingerprintFailure(result))
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      cb(false, tr("error.invalid-response"))
      return
    end
    local sanitized = {}
    local secrets = {}
    for _, rawItem in ipairs(decoded) do
      local s = vault.sanitize(rawItem)
      if s then
        table.insert(sanitized, s)
        if s.hasTotp and s.reprompt ~= true then
          local login = rawItem.login
          if type(login) == "table" and type(login.totp) == "string" and login.totp ~= "" then
            secrets[s.id] = login.totp
          end
        end
      end
    end
    runBw({ "list", "folders" }, function(folderResult)
      local folderList = {}
      if folderResult.ok then
        local decodedFolders = noctalia.json.decode(folderResult.stdout)
        if type(decodedFolders) == "table" then
          for _, f in ipairs(decodedFolders) do
            if type(f) == "table" and type(f.id) == "string" and type(f.name) == "string" then
              table.insert(folderList, { id = f.id, name = f.name })
            end
          end
        end
      end
      items = sanitized
      folders = folderList
      totpSecrets = secrets
      syncedAt = os.time()
      publishVault()
      cb(true)
    end, 20000)
  end, 45000)
end

local function syncAndRefresh(notifyDone, cb)
  runBw({ "sync" }, function(result)
    if not result.ok then
      -- sync can fail offline; the cached vault may still be usable
      log(`sync failed: {fingerprintFailure(result)}`)
    end
    refreshVault(function(ok, err)
      if notifyDone and ok then
        noctalia.notify(tr("title"), tr("notify.synced"))
      end
      cb(ok, err)
    end)
  end, 45000)
end

-- ── auth ─────────────────────────────────────────────────────────────────────

local function withPasswordFile(password, kind, fn)
  local dir = noctalia.getenv("XDG_RUNTIME_DIR")
  if type(dir) ~= "string" or dir == "" then
    dir = noctalia.pluginDataDir()
  end
  if type(dir) ~= "string" then
    dir = "/tmp"
  end
  local path = `{dir}/gery-bw-{kind}-{tostring(os.time())}-{tostring(math.random(100000, 999999))}.pw`
  local ok, err = noctalia.writeFile(path, password)
  if not ok then
    fn(nil, err or "cannot write password file")
    return
  end
  local function cleanup()
    noctalia.removeFile(path)
  end
  fn(path, nil, cleanup)
end

-- Verifies the master password by re-unlocking; invalidates the old session
-- key and installs the new one. Used for unlock and master-password reprompt.
local function verifyAndAdopt(password, cb)
  withPasswordFile(password, "pw", function(path, werr, cleanup)
    if path == nil then
      cb(false, werr)
      return
    end
    runBw({ "unlock", "--passwordfile", path, "--raw" }, function(result)
      if cleanup then
        cleanup()
      end
      if not result.ok then
        cb(false, fingerprintFailure(result))
        return
      end
      local newToken = trim(result.stdout)
      if newToken == "" then
        cb(false, tr("error.invalid-session"))
        return
      end
      token = newToken
      status.state = "unlocked"
      status.error = ""
      touchActivity()
      publishStatus()
      cb(true)
    end, 60000, { session = false })
  end)
end

-- ── command handlers ─────────────────────────────────────────────────────────

local dispatch
local enqueue

local function respond(cmd, ok, data, error)
  if type(cmd.seq) == "string" then
    noctalia.state.set("rsp", { seq = cmd.seq, action = cmd.action, ok = ok, data = data, error = error })
  end
end

local function ensureUnlocked(cmd, done)
  if status.state ~= "unlocked" or token == nil then
    done(false, nil, tr("error.vault-locked"))
    return false
  end
  return true
end

local function handleStatusPoll(_cmd, done)
  runBw({ "status" }, function(result)
    if not result.ok then
      status.error = fingerprintFailure(result)
      if result.timedOut then
        status.error = tr("error.timeout")
      end
      publishStatus()
      done(true)
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      done(true)
      return
    end
    status.email = type(decoded.userEmail) == "string" and decoded.userEmail or ""
    status.serverUrl = type(decoded.serverUrl) == "string" and decoded.serverUrl or ""
    status.error = ""
    if decoded.status == "unauthenticated" then
      clearSessionData()
      publishVault()
      status.state = "unauthenticated"
    elseif token == nil then
      status.state = "locked"
    else
      status.state = "unlocked"
    end
    publishStatus()
    done(true)
  end, 10000, { session = false })
end

local function handleUnlock(cmd, done)
  local password = cmd.password
  if type(password) ~= "string" or password == "" then
    done(false, nil, tr("error.password-required"))
    return
  end
  verifyAndAdopt(password, function(ok, err)
    if not ok then
      noctalia.notifyError(tr("title"), err or tr("error.unlock-failed"))
      done(false, nil, err)
      return
    end
    noctalia.notify(tr("title"), tr("notify.unlocked"))
    done(true)
    -- refresh the vault in the background; the queue serializes the work
    enqueue({ action = "ensure-fresh" })
  end)
end

local function handleReprompt(cmd, done)
  local password = cmd.password
  if type(password) ~= "string" or password == "" then
    done(false, nil, tr("error.password-required"))
    return
  end
  local wasUnlocked = status.state == "unlocked"
  verifyAndAdopt(password, function(ok, err)
    if not ok then
      done(false, nil, err or tr("error.unlock-failed"))
      return
    end
    local intent = pendingIntent
    pendingIntent = nil
    local function finishIntent()
      if intent ~= nil then
        dispatch(intent, function(intentOk, intentData, intentErr)
          done(intentOk, intentData, intentErr)
        end)
      else
        done(true)
      end
    end
    if wasUnlocked then
      finishIntent()
    else
      syncAndRefresh(false, function()
        finishIntent()
      end)
    end
  end)
end

local function handleBeginReprompt(cmd, done)
  local intent = cmd.intent
  if type(intent) ~= "table" or type(intent.action) ~= "string" then
    done(false, nil, tr("error.invalid-request"))
    return
  end
  pendingIntent = intent
  noctalia.state.set("reprompt", {
    description = type(cmd.description) == "string" and cmd.description or tr("reprompt.description"),
  })
  noctalia.togglePanel("gery/bitwarden:auth-reprompt")
  done(true)
end

local function handleLogin(cmd, done)
  local clientId = trim(cmd.clientId or "")
  local clientSecret = trim(cmd.clientSecret or "")
  if clientId == "" or clientSecret == "" then
    done(false, nil, tr("error.api-key-required"))
    return
  end
  local function doLogin()
    runBw({ "login", "--apikey" }, function(result)
      if not result.ok then
        local err = fingerprintFailure(result)
        if err == "" then
          err = tr("error.login-failed")
        end
        done(false, nil, err)
        return
      end
      clearSessionData()
      status.state = "locked"
      status.error = ""
      publishStatus()
      publishVault()
      noctalia.notify(tr("title"), tr("notify.logged-in"))
      noctalia.togglePanel("gery/bitwarden:auth-unlock")
      done(true)
    end, 60000, { session = false, env = { BW_CLIENTID = clientId, BW_CLIENTSECRET = clientSecret } })
  end
  local serverUrl = trim(cfg.str("server_url", ""))
  if serverUrl == "" then
    doLogin()
    return
  end
  runBw({ "config", "server", serverUrl }, function(result)
    if not result.ok then
      local err = fingerprintFailure(result)
      done(false, nil, err ~= "" and err or tr("error.server-config-failed"))
      return
    end
    doLogin()
  end, 15000, { session = false })
end

local function clearVaultState(state)
  clearSessionData()
  status.state = state
  status.error = ""
  publishStatus()
  publishVault()
end

local function handleLock(_cmd, done)
  runBw({ "lock" }, function(result)
    clearVaultState("locked")
    if not result.ok and not isEmptyOutput(result) then
      log(`lock: {fingerprintFailure(result)}`)
    end
    noctalia.notify(tr("title"), tr("notify.locked"))
    done(true)
  end, 15000, { session = false })
end

local function handleLogout(_cmd, done)
  runBw({ "logout" }, function(result)
    clearVaultState("unauthenticated")
    if not result.ok and not isEmptyOutput(result) then
      log(`logout: {fingerprintFailure(result)}`)
    end
    noctalia.notify(tr("title"), tr("notify.logged-out"))
    done(true)
  end, 20000, { session = false })
end

local function handleSync(_cmd, done)
  if not ensureUnlocked(nil, done) then
    return
  end
  syncAndRefresh(true, function(ok, err)
    done(ok, nil, err)
  end)
end

local function handleEnsureFresh(_cmd, done)
  if status.state ~= "unlocked" or token == nil then
    done(true)
    return
  end
  local now = noctalia.nowMs()
  if now - lastEnsureMs < 20000 then
    done(true)
    return
  end
  if syncedAt ~= 0 then
    local minutes = cfg.int("auto_sync_minutes", 15, 0, 1440)
    if minutes <= 0 or os.time() - syncedAt < minutes * 60 then
      done(true)
      return
    end
  end
  lastEnsureMs = now
  syncAndRefresh(false, function(ok, err)
    done(ok, nil, ok and nil or err)
  end)
end

local function handleGetItem(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  fetchItem(cmd.id, function(ok, item, err)
    done(ok, item, err)
  end)
end

local function handleTotpSecrets(_cmd, done)
  if status.state ~= "unlocked" then
    done(true, {})
    return
  end
  done(true, totpSecrets)
end

local function handleCopyField(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  resolveValue(cmd.id, cmd.path, function(ok, value, sensitive, err)
    if not ok then
      noctalia.notifyError(tr("title"), err or tr("error.not-found"))
      done(false, nil, err)
      return
    end
    doCopy(value, cmd.label or cmd.path, sensitive)
    done(true)
  end)
end

local function handlePasteField(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  resolveValue(cmd.id, cmd.path, function(ok, value, sensitive, err)
    if not ok then
      noctalia.notifyError(tr("title"), err or tr("error.not-found"))
      done(false, nil, err)
      return
    end
    doPaste(value, cmd.label or cmd.path, sensitive, function()
      done(true)
    end)
  end)
end

local function handleCopyValue(cmd, done)
  if type(cmd.value) ~= "string" then
    done(false, nil, tr("error.invalid-request"))
    return
  end
  doCopy(cmd.value, cmd.label or tr("fields.value"), cmd.sensitive == true)
  done(true)
end

local function handlePasteValue(cmd, done)
  if type(cmd.value) ~= "string" then
    done(false, nil, tr("error.invalid-request"))
    return
  end
  doPaste(cmd.value, cmd.label or tr("fields.value"), cmd.sensitive == true, function()
    done(true)
  end)
end

local function handleGenerate(cmd, done)
  local opts = cmd.opts
  if type(opts) ~= "table" then
    opts = nil
  end
  local args = cfg.generateArgs(opts)
  runBw(args, function(result)
    if not result.ok then
      local err = trim(result.stderr)
      done(false, nil, err ~= "" and err or tr("error.generate-failed"))
      return
    end
    local value = trim(result.stdout)
    if value == "" then
      done(false, nil, tr("error.generate-failed"))
      return
    end
    done(true, { value = value })
  end, 15000, { session = false })
end

local function handleQuickGenerate(cmd, done)
  local opts = cfg.generatorDefaults()
  opts.mode = cmd.mode == "passphrase" and "passphrase" or "password"
  runBw(cfg.generateArgs(opts), function(result)
    if not result.ok then
      noctalia.notifyError(tr("title"), tr("error.generate-failed"))
      done(false, nil, trim(result.stderr))
      return
    end
    local value = trim(result.stdout)
    doCopy(value, cmd.mode == "passphrase" and tr("notify.generated-passphrase") or tr("notify.generated"), true)
    done(true)
  end, 15000, { session = false })
end

-- ── create ───────────────────────────────────────────────────────────────────

local function decodeJsonOutput(result)
  local decoded = noctalia.json.decode(result.stdout)
  if type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local function encodeObject(value)
  local encoded = noctalia.json.encode(value)
  if type(encoded) ~= "string" or encoded == "" then
    return nil
  end
  return encoded
end

local function handleCreateLogin(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  if type(cmd.name) ~= "string" or trim(cmd.name) == "" or type(cmd.password) ~= "string" or cmd.password == "" then
    done(false, nil, tr("error.name-required"))
    return
  end
  runBw({ "get", "template", "item" }, function(itemResult)
    if not itemResult.ok then
      done(false, nil, fingerprintFailure(itemResult))
      return
    end
    local template = decodeJsonOutput(itemResult)
    if template == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    runBw({ "get", "template", "item.login" }, function(loginResult)
      local login = loginResult.ok and decodeJsonOutput(loginResult) or nil
      if login == nil then
        login = { username = nil, password = "", totp = nil, uris = {} }
      end
      template.name = cmd.name
      template.type = vault.TYPE.LOGIN
      if type(cmd.folderId) == "string" and cmd.folderId ~= "" then
        template.folderId = cmd.folderId
      end
      if type(cmd.notes) == "string" and cmd.notes ~= "" then
        template.notes = cmd.notes
      end
      login.username = (type(cmd.username) == "string" and cmd.username ~= "") and cmd.username or nil
      login.password = cmd.password
      login.totp = nil
      if type(cmd.uri) == "string" and cmd.uri ~= "" then
        login.uris = { { match = nil, uri = cmd.uri } }
      end
      template.login = login
      local encoded = encodeObject(template)
      if encoded == nil then
        done(false, nil, tr("error.invalid-response"))
        return
      end
      runBw({ "create", "item", b64.encode(encoded) }, function(createResult)
        if not createResult.ok then
          done(false, nil, fingerprintFailure(createResult))
          return
        end
        syncedAt = 0
        noctalia.notify(tr("title"), tr("notify.login-created", { name = cmd.name }))
        done(true, { name = cmd.name })
      end, 20000)
    end, 15000)
  end, 15000)
end

local function handleCreateFolder(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  if type(cmd.name) ~= "string" or trim(cmd.name) == "" then
    done(false, nil, tr("error.name-required"))
    return
  end
  runBw({ "get", "template", "folder" }, function(templateResult)
    if not templateResult.ok then
      done(false, nil, fingerprintFailure(templateResult))
      return
    end
    local template = decodeJsonOutput(templateResult)
    if template == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    template.name = cmd.name
    local encoded = encodeObject(template)
    if encoded == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    runBw({ "create", "folder", b64.encode(encoded) }, function(createResult)
      if not createResult.ok then
        done(false, nil, fingerprintFailure(createResult))
        return
      end
      syncedAt = 0
      noctalia.notify(tr("title"), tr("notify.folder-created", { name = cmd.name }))
      done(true, { name = cmd.name })
    end, 20000)
  end, 15000)
end

-- ── sends ────────────────────────────────────────────────────────────────────

local function sanitizeSend(s)
  if type(s) ~= "table" or type(s.id) ~= "string" then
    return nil
  end
  return {
    id = s.id,
    name = type(s.name) == "string" and s.name or "(unnamed)",
    type = type(s.type) == "number" and s.type or 0,
    accessUrl = type(s.accessUrl) == "string" and s.accessUrl or "",
    disabled = s.disabled == true,
    passwordSet = s.passwordSet == true,
    maxAccessCount = type(s.maxAccessCount) == "number" and s.maxAccessCount or nil,
    accessCount = type(s.accessCount) == "number" and s.accessCount or 0,
    deletionDate = type(s.deletionDate) == "string" and s.deletionDate or nil,
    expirationDate = type(s.expirationDate) == "string" and s.expirationDate or nil,
    hasNotes = type(s.notes) == "string" and s.notes ~= "",
    file = type(s.file) == "table" and { fileName = s.file.fileName } or nil,
  }
end

local function handleSendList(_cmd, done)
  if not ensureUnlocked(nil, done) then
    return
  end
  runBw({ "send", "list" }, function(result)
    if not result.ok then
      done(false, nil, fingerprintFailure(result))
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    local list = {}
    for _, s in ipairs(decoded) do
      local sanitized = sanitizeSend(s)
      if sanitized then
        table.insert(list, sanitized)
      end
    end
    done(true, { sends = list })
  end, 20000)
end

local function handleSendGet(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  runBw({ "get", "send", cmd.id }, function(result)
    if not result.ok then
      done(false, nil, fingerprintFailure(result))
      return
    end
    local decoded = decodeJsonOutput(result)
    if decoded == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    done(true, { send = decoded })
  end, 20000)
end

local function isoDate(offsetSeconds)
  return os.date("!%Y-%m-%dT%H:%M:%S", os.time() + offsetSeconds) .. ".000Z"
end

-- json.encode omits nil keys; callers encode a "__null__" marker for fields
-- that must be sent as explicit JSON null (e.g. clearing an expiry).
local function encodeWithNulls(value, nullKeys)
  local encoded = noctalia.json.encode(value)
  if encoded == nil then
    return nil
  end
  for _, key in ipairs(nullKeys or {}) do
    encoded = encoded:gsub('"' .. key .. '":"__null__"', '"' .. key .. '":null')
  end
  return encoded
end

local function handleSendCreate(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  if type(cmd.name) ~= "string" or trim(cmd.name) == "" then
    done(false, nil, tr("error.name-required"))
    return
  end
  local isFile = cmd.type == "file"
  local templateName = isFile and "send.file" or "send.text"
  local extraArgs = nil
  if isFile then
    if type(cmd.filePath) ~= "string" or cmd.filePath == "" then
      done(false, nil, tr("error.file-required"))
      return
    end
    local path = noctalia.expandPath(cmd.filePath)
    if not noctalia.fileExists(path) then
      done(false, nil, tr("error.file-not-found"))
      return
    end
    extraArgs = { "--file", path }
  else
    if type(cmd.text) ~= "string" or cmd.text == "" then
      done(false, nil, tr("error.text-required"))
      return
    end
  end
  runBw({ "get", "template", templateName }, function(templateResult)
    if not templateResult.ok then
      done(false, nil, fingerprintFailure(templateResult))
      return
    end
    local template = decodeJsonOutput(templateResult)
    if template == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    template.name = cmd.name
    template.notes = (type(cmd.notes) == "string" and cmd.notes ~= "") and cmd.notes or nil
    local deletionSeconds = tonumber(cmd.deletionSeconds) or 604800
    template.deletionDate = isoDate(deletionSeconds)
    local expirationSeconds = tonumber(cmd.expirationSeconds)
    template.expirationDate = expirationSeconds ~= nil and expirationSeconds > 0 and isoDate(expirationSeconds) or nil
    template.maxAccessCount = tonumber(cmd.maxAccessCount)
    template.password = (type(cmd.password) == "string" and cmd.password ~= "") and cmd.password or nil
    template.disabled = false
    template.hideEmail = cmd.hideEmail == true
    if isFile then
      local path = noctalia.expandPath(cmd.filePath)
      local info = noctalia.fileInfo(path)
      template.file = template.file or {}
      template.file.fileName = vault.basename(path)
      if type(info) == "table" and type(info.size) == "number" then
        template.file.size = tostring(info.size)
      end
      extraArgs = { "--file", path }
    else
      template.text = template.text or {}
      template.text.text = cmd.text
      template.text.hidden = cmd.hidden == true
    end
    local encoded = encodeObject(template)
    if encoded == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    local args = { "send", "create", b64.encode(encoded) }
    if extraArgs ~= nil then
      for _, a in ipairs(extraArgs) do
        table.insert(args, a)
      end
    end
    runBw(args, function(createResult)
      if not createResult.ok then
        done(false, nil, fingerprintFailure(createResult))
        return
      end
      local created = decodeJsonOutput(createResult)
      local accessUrl = created and created.accessUrl or ""
      if accessUrl ~= "" then
        doCopy(accessUrl, tr("notify.send-url"), false)
      end
      noctalia.notify(tr("title"), tr("notify.send-created", { name = cmd.name }))
      done(true, { id = created and created.id or nil, accessUrl = accessUrl })
    end, 30000)
  end, 15000)
end

local function handleSendEdit(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  runBw({ "get", "send", cmd.id }, function(getResult)
    if not getResult.ok then
      done(false, nil, fingerprintFailure(getResult))
      return
    end
    local send = decodeJsonOutput(getResult)
    if send == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    local nullKeys = {}
    if type(cmd.name) == "string" and cmd.name ~= "" then
      send.name = cmd.name
    end
    if cmd.notes ~= nil then
      send.notes = cmd.notes ~= "" and cmd.notes or nil
    end
    if tonumber(cmd.maxAccessCount) ~= nil then
      send.maxAccessCount = tonumber(cmd.maxAccessCount)
    else
      send.maxAccessCount = "__null__"
      table.insert(nullKeys, "maxAccessCount")
    end
    local expirationSeconds = tonumber(cmd.expirationSeconds)
    if expirationSeconds ~= nil and expirationSeconds > 0 then
      send.expirationDate = isoDate(expirationSeconds)
    else
      send.expirationDate = "__null__"
      table.insert(nullKeys, "expirationDate")
    end
    if tonumber(cmd.deletionSeconds) ~= nil and tonumber(cmd.deletionSeconds) > 0 then
      send.deletionDate = isoDate(tonumber(cmd.deletionSeconds))
    end
    if type(cmd.password) == "string" and cmd.password ~= "" then
      send.password = cmd.password
    end
    if cmd.hideEmail ~= nil then
      send.hideEmail = cmd.hideEmail == true
    end
    if cmd.disabled ~= nil then
      send.disabled = cmd.disabled == true
    end
    if cmd.type == "text" and cmd.text ~= nil then
      send.text = { text = cmd.text, hidden = cmd.hidden == true }
    end
    local encoded = encodeWithNulls(send, nullKeys)
    if encoded == nil then
      done(false, nil, tr("error.invalid-response"))
      return
    end
    runBw({ "send", "edit", b64.encode(encoded) }, function(editResult)
      if not editResult.ok then
        done(false, nil, fingerprintFailure(editResult))
        return
      end
      noctalia.notify(tr("title"), tr("notify.send-updated"))
      done(true)
    end, 30000)
  end, 20000)
end

local function handleSendDelete(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  runBw({ "send", "delete", cmd.id }, function(result)
    if not result.ok then
      done(false, nil, fingerprintFailure(result))
      return
    end
    noctalia.notify(tr("title"), tr("notify.send-deleted"))
    done(true)
  end, 20000)
end

local function handleSendRemovePassword(cmd, done)
  if not ensureUnlocked(cmd, done) then
    return
  end
  runBw({ "send", "remove-password", cmd.id }, function(result)
    if not result.ok then
      done(false, nil, fingerprintFailure(result))
      return
    end
    noctalia.notify(tr("title"), tr("notify.send-password-removed"))
    done(true)
  end, 20000)
end

local function handleSendReceive(cmd, done)
  local url = trim(cmd.url or "")
  if url == "" then
    done(false, nil, tr("error.url-required"))
    return
  end
  local password = cmd.password
  local function failFrom(result)
    local text = result.stderr ~= "" and result.stderr or result.stdout
    local lower = string.lower(text)
    if lower:find("invalid password", 1, true) then
      done(false, nil, tr("error.send-invalid-password"))
    elseif lower:find("send password", 1, true) or lower:find("password", 1, true) then
      done(false, nil, tr("error.send-needs-password"))
    else
      done(false, nil, trim(text) ~= "" and trim(text) or tr("error.receive-failed"))
    end
  end
  local function withOptionalPasswordFile(fn)
    if type(password) == "string" and password ~= "" then
      withPasswordFile(password, "send", function(path, werr, cleanup)
        if path == nil then
          done(false, nil, werr)
          return
        end
        fn(path, cleanup)
      end)
    else
      fn(nil, nil)
    end
  end
  withOptionalPasswordFile(function(passwordFile, cleanup)
    local args = { "send", "receive", url, "--obj" }
    if passwordFile ~= nil then
      table.insert(args, "--passwordfile")
      table.insert(args, passwordFile)
    end
    runBw(args, function(infoResult)
      if cleanup ~= nil then
        cleanup()
      end
      if not infoResult.ok then
        failFrom(infoResult)
        return
      end
      local info = decodeJsonOutput(infoResult)
      if info == nil then
        done(false, nil, tr("error.invalid-response"))
        return
      end
      local sendName = type(info.name) == "string" and info.name or ""
      if info.type == 0 then
        -- fetch the text content
        withOptionalPasswordFile(function(passwordFile2, cleanup2)
          local textArgs = { "send", "receive", url }
          if passwordFile2 ~= nil then
            table.insert(textArgs, "--passwordfile")
            table.insert(textArgs, passwordFile2)
          end
          runBw(textArgs, function(textResult)
            if cleanup2 ~= nil then
              cleanup2()
            end
            if not textResult.ok then
              failFrom(textResult)
              return
            end
            done(true, { kind = "text", name = sendName, text = textResult.stdout })
          end, 20000, { session = false })
        end)
        return
      end
      local fileName = "send-file"
      if type(info.file) == "table" and type(info.file.fileName) == "string" and info.file.fileName ~= "" then
        fileName = vault.basename(info.file.fileName)
      end
      local home = noctalia.getenv("HOME") or "/tmp"
      local dir = home .. "/Downloads"
      if not noctalia.fileExists(dir) then
        noctalia.mkdirAll(dir)
      end
      local outPath = dir .. "/" .. fileName
      withOptionalPasswordFile(function(passwordFile2, cleanup2)
        local fileArgs = { "send", "receive", url, "--output", outPath }
        if passwordFile2 ~= nil then
          table.insert(fileArgs, "--passwordfile")
          table.insert(fileArgs, passwordFile2)
        end
        runBw(fileArgs, function(fileResult)
          if cleanup2 ~= nil then
            cleanup2()
          end
          if not fileResult.ok then
            failFrom(fileResult)
            return
          end
          noctalia.notify(tr("title"), tr("notify.send-saved", { path = outPath }))
          done(true, { kind = "file", name = sendName, path = outPath })
        end, 30000, { session = false })
      end)
    end)
  end)
end

local function handleOpenUrl(cmd, done)
  local url = cmd.url
  if type(url) ~= "string" or url == "" then
    done(false, nil, tr("error.invalid-request"))
    return
  end
  local opener = expandBinary("xdg-open") or expandBinary("gio")
  if opener == nil then
    done(false, nil, tr("error.no-opener"))
    return
  end
  noctalia.runAsync({ opener, url })
  done(true)
end

local function handleFavoriteToggle(cmd, done)
  local id = cmd.id
  if type(id) ~= "string" or id == "" then
    done(false, nil, tr("error.invalid-request"))
    return
  end
  if favorites[id] == true then
    favorites[id] = nil
  else
    favorites[id] = true
  end
  persistFavorites()
  publishVault()
  done(true, { favorite = favorites[id] == true })
end

-- ── queue / dispatch ─────────────────────────────────────────────────────────

dispatch = function(cmd, done)
  local action = cmd.action
  if action == "status-poll" then
    handleStatusPoll(cmd, done)
  elseif action == "unlock" then
    handleUnlock(cmd, done)
  elseif action == "reprompt" then
    handleReprompt(cmd, done)
  elseif action == "begin-reprompt" then
    handleBeginReprompt(cmd, done)
  elseif action == "login" then
    handleLogin(cmd, done)
  elseif action == "lock" then
    handleLock(cmd, done)
  elseif action == "logout" then
    handleLogout(cmd, done)
  elseif action == "sync" then
    handleSync(cmd, done)
  elseif action == "ensure-fresh" then
    handleEnsureFresh(cmd, done)
  elseif action == "get-item" then
    handleGetItem(cmd, done)
  elseif action == "totp-secrets" then
    handleTotpSecrets(cmd, done)
  elseif action == "copy-field" then
    handleCopyField(cmd, done)
  elseif action == "paste-field" then
    handlePasteField(cmd, done)
  elseif action == "copy-value" then
    handleCopyValue(cmd, done)
  elseif action == "paste-value" then
    handlePasteValue(cmd, done)
  elseif action == "generate" then
    handleGenerate(cmd, done)
  elseif action == "quick-generate" then
    handleQuickGenerate(cmd, done)
  elseif action == "create-login" then
    handleCreateLogin(cmd, done)
  elseif action == "create-folder" then
    handleCreateFolder(cmd, done)
  elseif action == "send-list" then
    handleSendList(cmd, done)
  elseif action == "send-get" then
    handleSendGet(cmd, done)
  elseif action == "send-create" then
    handleSendCreate(cmd, done)
  elseif action == "send-edit" then
    handleSendEdit(cmd, done)
  elseif action == "send-delete" then
    handleSendDelete(cmd, done)
  elseif action == "send-remove-password" then
    handleSendRemovePassword(cmd, done)
  elseif action == "send-receive" then
    handleSendReceive(cmd, done)
  elseif action == "favorite-toggle" then
    handleFavoriteToggle(cmd, done)
  elseif action == "open-url" then
    handleOpenUrl(cmd, done)
  else
    log(`unknown command '{tostring(action)}'`)
    done(false, nil, tr("error.unknown-action"))
  end
end

local function pump()
  if busy or #queue == 0 then
    return
  end
  busy = true
  busyStartedMs = noctalia.nowMs()
  currentCmd = table.remove(queue, 1)
  publishStatus()
  publishVault()
  local finished = false
  local function done(ok, data, error)
    if finished then
      return
    end
    finished = true
    respond(currentCmd, ok, data, error)
    busy = false
    currentCmd = nil
    publishStatus()
    publishVault()
    pump()
  end
  dispatch(currentCmd, done)
end

enqueue = function(cmd)
  table.insert(queue, cmd)
  pump()
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

noctalia.state.watch("cmd", function(cmd)
  if type(cmd) ~= "table" or type(cmd.action) ~= "string" then
    return
  end
  enqueue(cmd)
end)

function update()
  tickCount += 1

  -- clipboard auto-clear
  if pendingClear ~= nil then
    if noctalia.nowMs() >= pendingClear.deadlineMs then
      local current = noctalia.clipboardText()
      if current == pendingClear.value then
        noctalia.copyToClipboard("", "text/plain;charset=utf-8")
      end
      pendingClear = nil
    end
  end

  -- operation watchdog
  if busy and noctalia.nowMs() - busyStartedMs > OP_WATCHDOG_MS then
    log("watchdog: operation timed out")
    if currentCmd ~= nil then
      respond(currentCmd, false, nil, tr("error.timeout"))
    end
    busy = false
    currentCmd = nil
    publishStatus()
    pump()
  end

  -- vault auto-lock
  if
    status.state == "unlocked"
    and token ~= nil
    and lockDeadlineMs ~= nil
    and noctalia.nowMs() >= lockDeadlineMs
    and not busy
  then
    lockDeadlineMs = nil
    log("vault timeout: locking")
    enqueue({ action = "lock" })
    return
  end

  if tickCount == 1 then
    resolveBinary()
    publishVault()
    publishStatus()
    if status.available then
      enqueue({ action = "status-poll" })
    else
      log("bw binary not found")
    end
    return
  end

  if tickCount % STATUS_POLL_TICKS == 0 and status.available and not busy and #queue == 0 then
    enqueue({ action = "status-poll" })
  end
end

function onConfigChanged()
  resolveBinary()
  publishStatus()
  publishVault()
end

function onIpc(event, _payload)
  if event == "refresh" then
    enqueue({ action = "status-poll" })
  elseif event == "lock" then
    enqueue({ action = "lock" })
  elseif event == "logout" then
    enqueue({ action = "logout" })
  elseif event == "sync" then
    enqueue({ action = "sync" })
  end
end

function onExit(_signal, reason)
  if binPath ~= nil and status.state == "unlocked" then
    -- on_restart semantics: the in-memory session dies with the runtime anyway,
    -- this also invalidates the CLI-side session key.
    noctalia.runAsync({ binPath, "lock" })
  end
  if reason == "disable" or reason == "uninstall" then
    log("service stopping")
  end
end

loadFavorites()
publishStatus()
publishVault()
