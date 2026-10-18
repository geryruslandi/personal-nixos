--!nonstrict
-- Create Folder panel (Raycast's Create Folder form).

local rpc = require("./lib/rpc.luau")

rpc.init()

local name = ""
local busy = false
local errorText = nil
local frameAcc = 0

local render -- forward

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

render = function()
  local status = noctalia.state.get("status") or {}
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = tr("create-folder.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
  }
  if status.state ~= "unlocked" then
    table.insert(children, ui.label({ text = tr("create-folder.locked"), color = "on_surface_variant" }))
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
    key = "folder-name",
    value = name,
    placeholder = tr("create-folder.name"),
    focus = true,
    submitOnEnter = true,
    onChange = function(v)
      name = v
    end,
    onSubmit = function(v)
      name = v
      submit()
    end,
  }))
  if busy then
    table.insert(children, ui.label({ text = tr("create-folder.creating"), color = "primary" }))
  elseif errorText ~= nil then
    table.insert(children, ui.label({ text = errorText, color = "error", maxLines = 2 }))
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
      text = tr("create-folder.create"),
      variant = "primary",
      enabled = not busy,
      onClick = submit,
    }),
  }))
  panel.render(ui.column({ gap = 12, align = "stretch" }, children))
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
  busy = true
  errorText = nil
  panel.setNeedsFrameTick(true)
  render()
  rpc.send("create-folder", { name = name }, function(ok, _data, err)
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
  name = ""
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
