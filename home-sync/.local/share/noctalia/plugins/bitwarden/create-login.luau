--!nonstrict
-- Create Login panel (Raycast's Create Login form): name, username, password
-- (with Bitwarden generator), URI and folder.

local rpc = require("./lib/rpc.luau")

rpc.init()

local name = ""
local username = ""
local password = ""
local uri = ""
local folders = {}
local folderIndex = 0
local genCounter = 0
local busy = false
local errorText = nil
local frameAcc = 0

local render -- forward
local submit -- forward
local doGenerate -- forward

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

render = function()
  local status = noctalia.state.get("status") or {}
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = tr("create-login.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
  }

  if status.state ~= "unlocked" then
    table.insert(children, ui.label({ text = tr("create-login.locked"), color = "on_surface_variant" }))
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

  table.insert(children, ui.input({
    key = "name",
    value = name,
    placeholder = tr("create-login.name"),
    focus = true,
    onChange = function(v)
      name = v
    end,
  }))
  table.insert(children, ui.input({
    key = "username",
    value = username,
    placeholder = tr("create-login.username"),
    onChange = function(v)
      username = v
    end,
  }))
  table.insert(children, ui.row({ gap = 8, align = "center" }, {
    ui.input({
      key = "password-" .. tostring(genCounter),
      value = password,
      placeholder = tr("create-login.password"),
      password = true,
      flexGrow = 1,
      onChange = function(v)
        password = v
      end,
    }),
    ui.button({ text = tr("create-login.generate"), glyph = "wand", enabled = not busy, onClick = doGenerate }),
  }))
  table.insert(children, ui.input({
    key = "uri",
    value = uri,
    placeholder = tr("create-login.uri"),
    onChange = function(v)
      uri = v
    end,
  }))
  local options = { tr("create-login.no-folder") }
  for _, f in ipairs(folders) do
    table.insert(options, f.name)
  end
  if #options > 1 then
    table.insert(children, ui.column({ gap = 6, align = "stretch" }, {
      ui.label({ text = tr("create-login.folder"), color = "on_surface_variant" }),
      ui.select({
        options = options,
        selectedIndex = folderIndex,
        onChange = function(index)
          folderIndex = tonumber(index) or 0
          render()
        end,
      }),
    }))
  end
  if busy then
    table.insert(children, ui.label({ text = tr("create-login.creating"), color = "primary" }))
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
      text = tr("create-login.create"),
      variant = "primary",
      enabled = not busy,
      onClick = submit,
    }),
  }))
  panel.render(ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

doGenerate = function()
  if busy then
    return
  end
  busy = true
  errorText = nil
  panel.setNeedsFrameTick(true)
  render()
  rpc.send("generate", nil, function(ok, data, err)
    busy = false
    if ok and type(data) == "table" then
      password = data.value
      genCounter += 1
      rpc.notify("copy-value", { value = password, label = tr("gen.generated"), sensitive = true })
    else
      errorText = err or tr("error.generate-failed")
    end
    render()
  end)
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
  if password == "" then
    errorText = tr("error.password-required")
    render()
    return
  end
  local folderId = nil
  if folderIndex > 0 and folders[folderIndex] ~= nil then
    folderId = folders[folderIndex].id
  end
  busy = true
  errorText = nil
  panel.setNeedsFrameTick(true)
  render()
  rpc.send("create-login", {
    name = name,
    username = username,
    password = password,
    uri = uri,
    folderId = folderId,
  }, function(ok, _data, err)
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
  local vaultState = noctalia.state.get("vault") or {}
  folders = vaultState.folders or {}
  name, username, password, uri = "", "", "", ""
  folderIndex = 0
  genCounter = 0
  busy = false
  errorText = nil
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
