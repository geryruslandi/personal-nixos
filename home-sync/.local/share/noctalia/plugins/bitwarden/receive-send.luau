--!nonstrict
-- Receive Send panel (Raycast's Receive Send): URL + optional password, then
-- shows the text content or saves a file send to ~/Downloads.

local rpc = require("./lib/rpc.luau")

rpc.init()

local url = ""
local password = ""
local state = "idle" -- idle | busy | text | file | error
local result = nil
local errorText = nil
local frameAcc = 0

local render -- forward

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function doReceive()
  if state == "busy" then
    return
  end
  if url == "" then
    state = "error"
    errorText = tr("error.url-required")
    render()
    return
  end
  state = "busy"
  errorText = nil
  panel.setNeedsFrameTick(true)
  render()
  rpc.send("send-receive", { url = url, password = password }, function(ok, data, err)
    if ok and type(data) == "table" then
      result = data
      state = data.kind == "file" and "file" or "text"
    else
      state = "error"
      errorText = err or tr("error.receive-failed")
    end
    render()
  end)
end

render = function()
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = tr("receive-send.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
  }

  if state == "text" and result ~= nil then
    table.insert(children, ui.label({
      text = result.name ~= "" and result.name or tr("receive-send.text"),
      fontWeight = "medium",
      flexGrow = 0,
    }))
    table.insert(children, ui.scroll({
      flexGrow = 1,
      fill = "surface_variant/0.4",
      radius = 10,
      padding = 12,
      align = "stretch",
    }, {
      ui.label({ text = result.text or "" }),
    }))
    table.insert(children, ui.row({ gap = 8, justify = "end" }, {
      ui.button({
        text = tr("receive-send.reset"),
        variant = "secondary",
        onClick = function()
          state = "idle"
          result = nil
          render()
        end,
      }),
      ui.button({
        text = tr("receive-send.copy-text"),
        variant = "primary",
        onClick = function()
          rpc.notify("copy-value", { value = result.text or "", label = tr("receive-send.text"), sensitive = true })
        end,
      }),
    }))
    panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children))
    return
  end

  if state == "file" and result ~= nil then
    table.insert(children, ui.label({
      text = tr("receive-send.saved", { path = result.path or "" }),
      maxLines = 3,
    }))
    table.insert(children, ui.row({ gap = 8, justify = "end" }, {
      ui.button({
        text = tr("receive-send.reset"),
        variant = "secondary",
        onClick = function()
          state = "idle"
          result = nil
          render()
        end,
      }),
      ui.button({
        text = tr("receive-send.copy-path"),
        variant = "primary",
        onClick = function()
          rpc.notify("copy-value", { value = result.path or "", label = tr("fields.path") })
        end,
      }),
    }))
    panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children))
    return
  end

  table.insert(children, ui.input({
    key = "send-url",
    value = url,
    placeholder = tr("receive-send.url"),
    focus = true,
    onChange = function(v)
      url = v
    end,
  }))
  table.insert(children, ui.input({
    key = "send-password",
    value = password,
    placeholder = tr("receive-send.password"),
    password = true,
    onChange = function(v)
      password = v
    end,
  }))
  if state == "busy" then
    table.insert(children, ui.label({ text = tr("receive-send.receiving"), color = "primary" }))
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
      text = tr("receive-send.receive"),
      variant = "primary",
      enabled = state ~= "busy",
      onClick = doReceive,
    }),
  }))
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

function onOpen(_context)
  url = ""
  password = ""
  state = "idle"
  result = nil
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
