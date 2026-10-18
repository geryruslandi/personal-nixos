--!nonstrict
-- Shared form for the three auth panels: unlock, login (API key), reprompt.
-- Returns a table of functions; each panel entry maps them to its globals
-- (modules have their own global env, so lifecycle hooks must live in the
-- entry script).

local rpc = require("./rpc.luau")

local M = {}

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

function M.new(kind)
  rpc.init()

  local password = ""
  local clientId = ""
  local clientSecret = ""
  local busy = false
  local errorText = nil
  local frameAcc = 0
  local submit -- forward

  local function request(action, payload, cb)
    panel.setNeedsFrameTick(true)
    rpc.send(action, payload, cb)
  end

  local function render()
    local titleKey = "auth.unlock.title"
    if kind == "login" then
      titleKey = "auth.login.title"
    elseif kind == "reprompt" then
      titleKey = "auth.reprompt.title"
    end
    local children = {
      ui.label({ text = tr(titleKey), fontSize = 16, fontWeight = "bold" }),
    }
    if kind == "reprompt" then
      local repromptState = noctalia.state.get("reprompt") or {}
      table.insert(children, ui.label({
        text = repromptState.description or tr("reprompt.description"),
        color = "on_surface_variant",
        maxLines = 3,
      }))
    end
    if kind == "login" then
      table.insert(children, ui.input({
        key = "client-id",
        placeholder = tr("auth.login.client-id"),
        focus = true,
        onChange = function(v)
          clientId = v
        end,
      }))
      table.insert(children, ui.input({
        key = "client-secret",
        placeholder = tr("auth.login.client-secret"),
        password = true,
        onChange = function(v)
          clientSecret = v
        end,
      }))
      table.insert(children, ui.label({
        text = tr("auth.login.hint"),
        color = "on_surface_variant",
        fontSize = 11,
      }))
    else
      table.insert(children, ui.input({
        key = kind .. "-password",
        placeholder = tr("auth.password-placeholder"),
        password = true,
        focus = true,
        submitOnEnter = true,
        onChange = function(v)
          password = v
        end,
        onSubmit = function(v)
          password = v
          submit()
        end,
      }))
    end
    if busy then
      table.insert(children, ui.label({ text = tr("auth.working"), color = "primary" }))
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
        text = kind == "login" and tr("auth.login.button") or tr("auth.submit"),
        variant = "primary",
        enabled = not busy,
        onClick = function()
          submit()
        end,
      }),
    }))
    panel.render(ui.column({ gap = 12, align = "stretch" }, children))
  end

  submit = function()
    if busy then
      return
    end
    local action, payload
    if kind == "login" then
      if clientId == "" or clientSecret == "" then
        errorText = tr("error.api-key-required")
        render()
        return
      end
      action = "login"
      payload = { clientId = clientId, clientSecret = clientSecret }
    elseif kind == "reprompt" then
      if password == "" then
        errorText = tr("error.password-required")
        render()
        return
      end
      action = "reprompt"
      payload = { password = password }
    else
      if password == "" then
        errorText = tr("error.password-required")
        render()
        return
      end
      action = "unlock"
      payload = { password = password }
    end
    busy = true
    errorText = nil
    render()
    request(action, payload, function(ok, _data, err)
      busy = false
      if ok then
        panel.close()
        return
      end
      errorText = err or tr("error.unlock-failed")
      password = ""
      render()
    end)
  end

  local function tick(deltaMs)
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

  return {
    open = function()
      busy = false
      errorText = nil
      password = ""
      render()
    end,
    tick = tick,
  }
end

return M
