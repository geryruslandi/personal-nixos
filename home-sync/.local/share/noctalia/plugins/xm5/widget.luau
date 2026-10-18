-- Bar widget: connected device + battery + noise-cancelling state.
-- Click opens the control panel.

local xm5 = require("./lib/xm5.luau")

local state = nil

local function tooltip()
  if state == nil then
    return "WH-1000XM5\nDaemon starting\u{2026}"
  end
  local lines = { state.model or "Sony headphones" }
  if state.firmware then
    table.insert(lines, "FW " .. tostring(state.firmware))
  end
  if state.battery then
    local charging = state.charging and state.charging ~= "not_charging"
    table.insert(lines, "Battery: " .. tostring(state.battery) .. "%" .. (charging and " (charging)" or ""))
  end
  if state.noise then
    local label = state.noise == "anc" and "Noise cancelling"
      or state.noise == "ambient" and "Ambient sound" or "Off"
    if state.noise == "ambient" and state.ambient_level then
      label = label .. " (" .. tostring(state.ambient_level) .. ")"
    end
    table.insert(lines, "Noise: " .. label)
  end
  if state.speak_to_chat ~= nil then
    table.insert(lines, "Speak-to-Chat: " .. (state.speak_to_chat and "on" or "off"))
  end
  if state.dsee ~= nil then
    table.insert(lines, "DSEE Extreme: " .. (state.dsee and "on" or "off"))
  end
  if state.connection then
    table.insert(lines, "Connection: " .. tostring(state.connection))
  end
  if state.volume then
    table.insert(lines, "Volume: " .. tostring(state.volume))
  end
  if state.connected == false then
    table.insert(lines, "Disconnected (last known values)")
  end
  table.insert(lines, "Click to open controls")
  return table.concat(lines, "\n")
end

local function render()
  local connected = state ~= nil and state.connected == true
  local noise = state and state.noise or nil
  local accent = xm5.noiseColor(noise)
  local deviceColor = connected and "on_surface" or xm5.COLOR_OFF
  local battColor = connected and xm5.batteryColor(state and state.battery) or xm5.COLOR_OFF

  barWidget.setTooltip(tooltip())

  local children = {
    ui.glyph({ name = xm5.noiseGlyph(noise), size = 15, color = accent }),
  }
  if state ~= nil then
    table.insert(children, ui.label({
      text = xm5.deviceShort(state.model),
      fontSize = 11,
      color = deviceColor,
    }))
    if state.noise ~= nil then
      table.insert(children, ui.label({
        text = xm5.noiseShort(state.noise),
        fontSize = 10,
        color = accent,
        fontWeight = "medium",
      }))
    end
    if type(state.battery) == "number" then
      table.insert(children, ui.label({
        text = tostring(state.battery) .. "%",
        fontSize = 11,
        color = battColor,
        fontWeight = "bold",
      }))
    end
  else
    barWidget.setGlyph("headphones")
    barWidget.setGlyphColor(xm5.COLOR_OFF)
    barWidget.setText("\u{2026}")
    return
  end

  local tree
  if barWidget.isVertical() then
    tree = ui.column({ gap = 2, align = "center", justify = "center" }, children)
  else
    tree = ui.row({ gap = 6, align = "center", justify = "center" }, children)
  end
  barWidget.render(tree)
end

noctalia.state.watch("xm5", function(value)
  state = value
  render()
end)

function update()
  local v = noctalia.state.get("xm5")
  state = v
  render()
end

function onClick()
  noctalia.togglePanel("gery/xm5:xm5-panel")
end

render()
