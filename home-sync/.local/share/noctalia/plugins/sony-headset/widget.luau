-- Bar widget: connected Sony device + battery + noise-cancelling state.
-- Click opens the control panel.

local sony = require("./lib/sony.luau")

local state = nil

local function deviceName()
  if state == nil then
    return "Sony headphones"
  end
  return state.model or state.device_name or "Sony headphones"
end

-- Main battery, falling back to per-bud levels for earbuds.
local function mainBattery()
  if state == nil then
    return nil
  end
  if type(state.battery) == "number" then
    return state.battery
  end
  if type(state.battery_left) == "number" and type(state.battery_right) == "number" then
    return math.floor((state.battery_left + state.battery_right) / 2)
  end
  return state.battery_left or state.battery_right
end

local function charging()
  if state == nil then
    return false
  end
  local c = state.charging or state.charging_left or "not_charging"
  return c ~= "not_charging"
end

local function tooltip()
  if state == nil then
    return "Sony headphones\nDaemon starting\u{2026}"
  end
  local lines = { deviceName() }
  if state.firmware then
    table.insert(lines, "FW " .. tostring(state.firmware))
  end
  local batt = mainBattery()
  if batt then
    table.insert(lines, "Battery: " .. tostring(batt) .. "%" .. (charging() and " (charging)" or ""))
    if state.battery_left or state.battery_right then
      table.insert(lines, "  L " .. tostring(state.battery_left or "?") .. "%  R " .. tostring(state.battery_right or "?") .. "%")
    end
    if state.battery_case then
      table.insert(lines, "  Case " .. tostring(state.battery_case) .. "%")
    end
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
  local accent = sony.noiseColor(noise)
  local deviceColor = connected and "on_surface" or sony.COLOR_OFF
  local batt = mainBattery()
  local battColor = connected and sony.batteryColor(batt) or sony.COLOR_OFF

  barWidget.setTooltip(tooltip())

  if state == nil then
    barWidget.setGlyph("headphones")
    barWidget.setGlyphColor(sony.COLOR_OFF)
    barWidget.setText("\u{2026}")
    return
  end

  local children = {
    ui.glyph({ name = sony.noiseGlyph(noise), size = 15, color = accent }),
    ui.label({ text = sony.deviceShort(state.model or state.device_name), fontSize = 11, color = deviceColor }),
  }
  if state.noise ~= nil then
    table.insert(children, ui.label({
      text = sony.noiseShort(state.noise),
      fontSize = 10,
      color = accent,
      fontWeight = "medium",
    }))
  end
  if type(batt) == "number" then
    table.insert(children, ui.label({
      text = tostring(batt) .. "%",
      fontSize = 11,
      color = battColor,
      fontWeight = "bold",
    }))
  end

  local tree
  if barWidget.isVertical() then
    tree = ui.column({ gap = 2, align = "center", justify = "center" }, children)
  else
    tree = ui.row({ gap = 6, align = "center", justify = "center" }, children)
  end
  barWidget.render(tree)
end

noctalia.state.watch("headset", function(value)
  state = value
  render()
end)

function update()
  state = noctalia.state.get("headset")
  render()
end

function onClick()
  noctalia.togglePanel("gery/sony-headset:headset-panel")
end

render()
