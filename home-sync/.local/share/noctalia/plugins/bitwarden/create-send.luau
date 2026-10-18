--!nonstrict
-- Create / Edit Send panel (Raycast's Create Send form + edit mode reached
-- from the sends list). Text and file sends, password, access count, expiry,
-- deletion date, notes and flags.

local rpc = require("./lib/rpc.luau")

rpc.init()

local DELETE_OPTIONS = {
  { key = "send-date.1h", seconds = 3600 },
  { key = "send-date.1d", seconds = 86400 },
  { key = "send-date.2d", seconds = 172800 },
  { key = "send-date.3d", seconds = 259200 },
  { key = "send-date.7d", seconds = 604800 },
  { key = "send-date.30d", seconds = 2592000 },
}

local mode = "create"
local sendId = nil
local sendType = "text"
local name = ""
local text = ""
local filePath = ""
local fileName = ""
local password = ""
local passwordSet = false
local notes = ""
local maxAccess = ""
local hidden = false
local disabled = false
local hideEmail = false
local deletionIndex = 4 -- 7 days, 0-based into DELETE_OPTIONS
local expirationIndex = 0 -- 0 = Never; else 1..6 into [Never] + DELETE_OPTIONS
local busy = false
local loading = false
local errorText = nil
local frameAcc = 0

local render -- forward
local submit -- forward

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function parseIso(iso)
  if type(iso) ~= "string" then
    return nil
  end
  local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if y == nil then
    return nil
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
    isdst = false,
  })
end

local function nearestDeleteIndex(iso)
  local t = parseIso(iso)
  if t == nil then
    return 4
  end
  local remaining = t - os.time()
  if remaining < 0 then
    return 1
  end
  local best = 1
  for i, opt in ipairs(DELETE_OPTIONS) do
    if math.abs(opt.seconds - remaining) < math.abs(DELETE_OPTIONS[best].seconds - remaining) then
      best = i
    end
  end
  return best
end

local function sectionLabel(title)
  return ui.label({ text = title, fontWeight = "medium", color = "on_surface_variant" })
end

local function render()
  local status = noctalia.state.get("status") or {}
  local isEdit = mode == "edit"
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({
        text = isEdit and tr("send-form.edit-title") or tr("send-form.create-title"),
        fontSize = 16,
        fontWeight = "bold",
        flexGrow = 1,
      }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
  }

  if status.state ~= "unlocked" then
    table.insert(children, ui.label({ text = tr("send-form.locked"), color = "on_surface_variant" }))
    table.insert(children, ui.row({ gap = 8, justify = "end" }, {
      ui.button({
        text = tr("root.unlock"),
        variant = "primary",
        onClick = function()
          noctalia.togglePanel("gery/bitwarden:auth-unlock")
        end,
      }),
    }))
    panel.render(ui.column({ gap = 12, align = "stretch" }, children))
    return
  end

  if loading then
    table.insert(children, ui.label({ text = tr("send-form.loading"), color = "primary" }))
    panel.render(ui.column({ gap = 12, align = "stretch" }, children))
    return
  end

  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.type")),
    ui.select({
      options = { tr("send-form.type-text"), tr("send-form.type-file") },
      selectedIndex = sendType == "file" and 1 or 0,
      enabled = not isEdit,
      onChange = function(index)
        sendType = tonumber(index) == 1 and "file" or "text"
        render()
      end,
    }),
  }))

  table.insert(children, ui.input({
    key = "send-name",
    value = name,
    placeholder = tr("send-form.name"),
    focus = true,
    onChange = function(v)
      name = v
    end,
  }))

  if sendType == "file" then
    if isEdit then
      table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
        sectionLabel(tr("send-form.file")),
        ui.label({ text = fileName ~= "" and fileName or tr("send-form.file"), color = "on_surface" }),
      }))
    else
      table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
        sectionLabel(tr("send-form.file-path")),
        ui.input({
          key = "send-file",
          value = filePath,
          placeholder = tr("send-form.file-path-hint"),
          onChange = function(v)
            filePath = v
          end,
        }),
      }))
    end
  else
    table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
      sectionLabel(tr("send-form.text")),
      ui.input({
        key = "send-text",
        value = text,
        placeholder = tr("send-form.text-hint"),
        multiline = true,
        height = 110,
        onChange = function(v)
          text = v
        end,
      }),
    }))
    table.insert(children, ui.row({ gap = 10, align = "center" }, {
      ui.toggle({
        checked = hidden,
        onChange = function(v)
          hidden = v == "true"
          render()
        end,
      }),
      ui.label({ text = tr("send-form.hidden"), flexGrow = 1 }),
    }))
  end

  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.password")),
    ui.input({
      key = "send-password",
      value = "",
      placeholder = isEdit and passwordSet and tr("send-form.password-keep") or tr("send-form.password-hint"),
      password = true,
      onChange = function(v)
        password = v
      end,
    }),
  }))

  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.max-access")),
    ui.input({
      key = "send-max-access",
      value = maxAccess,
      placeholder = tr("send-form.max-access-hint"),
      onChange = function(v)
        maxAccess = v
      end,
    }),
  }))

  local deleteOptions = {}
  for _, opt in ipairs(DELETE_OPTIONS) do
    table.insert(deleteOptions, tr(opt.key))
  end
  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.deletion")),
    ui.select({
      options = deleteOptions,
      selectedIndex = deletionIndex,
      onChange = function(index)
        deletionIndex = tonumber(index) or 4
        render()
      end,
    }),
  }))
  local expirationOptions = { tr("send-form.never") }
  for _, opt in ipairs(DELETE_OPTIONS) do
    table.insert(expirationOptions, tr(opt.key))
  end
  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.expiration")),
    ui.select({
      options = expirationOptions,
      selectedIndex = expirationIndex,
      onChange = function(index)
        expirationIndex = tonumber(index) or 0
        render()
      end,
    }),
  }))

  table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
    sectionLabel(tr("send-form.notes")),
    ui.input({
      key = "send-notes",
      value = notes,
      placeholder = tr("send-form.notes-hint"),
      multiline = true,
      height = 70,
      onChange = function(v)
        notes = v
      end,
    }),
  }))

  table.insert(children, ui.row({ gap = 10, align = "center" }, {
    ui.toggle({
      checked = hideEmail,
      onChange = function(v)
        hideEmail = v == "true"
        render()
      end,
    }),
    ui.label({ text = tr("send-form.hide-email"), flexGrow = 1 }),
  }))
  if isEdit then
    table.insert(children, ui.row({ gap = 10, align = "center" }, {
      ui.toggle({
        checked = disabled,
        onChange = function(v)
          disabled = v == "true"
          render()
        end,
      }),
      ui.label({ text = tr("send-form.disabled"), flexGrow = 1 }),
    }))
  end

  if busy then
    table.insert(children, ui.label({ text = tr("send-form.saving"), color = "primary" }))
  elseif errorText ~= nil then
    table.insert(children, ui.label({ text = errorText, color = "error", maxLines = 3 }))
  end

  table.insert(children, ui.row({ gap = 8, justify = "end" }, {
    ui.button({
      text = tr("auth.cancel"),
      variant = "secondary",
      onClick = function()
        panel.close()
      end,
    }),
    ui.button({
      text = isEdit and tr("send-form.save") or tr("send-form.create"),
      variant = "primary",
      enabled = not busy,
      onClick = submit,
    }),
  }))
  panel.render(ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

local function applySend(send)
  name = type(send.name) == "string" and send.name or ""
  notes = type(send.notes) == "string" and send.notes or ""
  maxAccess = type(send.maxAccessCount) == "number" and tostring(send.maxAccessCount) or ""
  password = ""
  passwordSet = send.passwordSet == true
  disabled = send.disabled == true
  hideEmail = send.hideEmail == true
  if send.type == 1 then
    sendType = "file"
    fileName = type(send.file) == "table" and tostring(send.file.fileName or "") or ""
  else
    sendType = "text"
    hidden = type(send.text) == "table" and send.text.hidden == true or false
    text = type(send.text) == "table" and tostring(send.text.text or "") or ""
  end
  deletionIndex = nearestDeleteIndex(send.deletionDate) - 1
  if type(send.expirationDate) == "string" and send.expirationDate ~= "" then
    expirationIndex = nearestDeleteIndex(send.expirationDate)
  else
    expirationIndex = 0
  end
end

submit = function()
  if busy then
    return
  end
  if name == "" then
    errorText = tr("error.name-required")
    render()
    return
  end
  if sendType == "text" and text == "" then
    errorText = tr("error.text-required")
    render()
    return
  end
  if sendType == "file" and mode == "create" and filePath == "" then
    errorText = tr("error.file-required")
    render()
    return
  end
  local payload = {
    name = name,
    notes = notes,
    type = sendType,
    text = text,
    hidden = hidden,
    filePath = filePath,
    password = password,
    maxAccessCount = tonumber(maxAccess),
    deletionSeconds = DELETE_OPTIONS[deletionIndex + 1].seconds,
    expirationSeconds = expirationIndex > 0 and DELETE_OPTIONS[expirationIndex].seconds or 0,
    hideEmail = hideEmail,
    disabled = disabled,
  }
  if mode == "edit" then
    payload.id = sendId
  end
  busy = true
  errorText = nil
  panel.setNeedsFrameTick(true)
  render()
  rpc.send(mode == "edit" and "send-edit" or "send-create", payload, function(ok, _data, err)
    busy = false
    if ok then
      panel.close()
      return
    end
    errorText = err or tr("error.create-failed")
    render()
  end)
end

function onOpen(_context)
  loading = false
  busy = false
  errorText = nil
  password = ""
  passwordSet = false
  name, text, filePath, fileName, notes, maxAccess = "", "", "", "", "", ""
  hidden, disabled, hideEmail = false, false, false
  deletionIndex = 4
  expirationIndex = 0
  sendType = "text"
  local editState = noctalia.state.get("send-edit")
  if type(editState) == "table" and type(editState.id) == "string" then
    mode = "edit"
    sendId = editState.id
    loading = true
    panel.setNeedsFrameTick(true)
    render()
    rpc.send("send-get", { id = sendId }, function(ok, data, err)
      loading = false
      if ok and type(data) == "table" and type(data.send) == "table" then
        applySend(data.send)
      else
        errorText = err or tr("error.invalid-response")
      end
      render()
    end)
    return
  end
  mode = "create"
  sendId = nil
  render()
end

function onFrameTick(deltaMs)
  frameAcc += deltaMs or 0
  if frameAcc < 1000 then
    return
  end
  frameAcc = 0
  if rpc.pendingCount() == 0 then
    panel.setNeedsFrameTick(false)
    return
  end
  rpc.expire()
  if rpc.pendingCount() == 0 then
    panel.setNeedsFrameTick(false)
  end
end
