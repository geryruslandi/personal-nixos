--!nonstrict
-- Control panel for gery/xm5: every XM5 feature behind one surface.

local xm5 = require("./lib/xm5.luau")

local state = nil
local seq = 0
local pending = {}
local render = nil

local function req(action, payload)
  seq = seq + 1
  local r = { seq = seq, action = action }
  if type(payload) == "table" then
    for k, v in pairs(payload) do
      r[k] = v
    end
  end
  noctalia.state.set("request", r)
end

local function caps()
  local c = state and state.capabilities or {}
  return c
end

local function card(title, children)
  local kids = {}
  if title then
    table.insert(kids, ui.label({ text = title, fontSize = 12, color = "primary", fontWeight = "bold" }))
  end
  for _, c in ipairs(children) do
    table.insert(kids, c)
  end
  return ui.column({
    gap = 8,
    paddingH = 12,
    paddingV = 10,
    radius = 12,
    fill = "surface_variant/0.4",
    border = "outline/0.3",
    borderWidth = 1,
    align = "stretch",
  }, kids)
end

local function row(label, control)
  return ui.row({ gap = 10, align = "center", justify = "space_between" }, {
    ui.label({ text = label, fontSize = 12, color = "on_surface", flexGrow = 1 }),
    control,
  })
end

local function toggle(checked, onChange)
  return ui.toggle({ checked = checked == true, onChange = onChange })
end

local function segment(items, selected, onSelect)
  local buttons = {}
  for _, item in ipairs(items) do
    local isSel = item.key == selected
    table.insert(buttons, ui.button({
      key = "seg-" .. item.key,
      text = item.label,
      variant = isSel and "primary" or "ghost",
      selected = isSel,
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        onSelect(item.key)
      end,
    }))
  end
  return ui.row({ gap = 6, align = "stretch" }, buttons)
end

local function ambientLevel()
  if pending.ambient_level ~= nil then
    return pending.ambient_level
  end
  return state and state.ambient_level or 0
end

local function volumeLevel()
  if pending.volume ~= nil then
    return pending.volume
  end
  return state and state.volume or 0
end

local function buildTree()
  local kids = {}

  -- Header -------------------------------------------------------------
  local connected = state ~= nil and state.connected == true
  local accent = xm5.noiseColor(state and state.noise)
  kids[#kids + 1] = ui.row({ gap = 10, align = "center", width = "fill" }, {
    ui.glyph({ name = xm5.noiseGlyph(state and state.noise), size = 26, color = accent }),
    ui.column({ gap = 1, flexGrow = 1, align = "start" }, {
      ui.label({
        text = state and state.model or "Sony headphones",
        fontSize = 15,
        color = "on_surface",
        fontWeight = "bold",
      }),
      ui.label({
        text = (state and state.firmware and ("Firmware " .. tostring(state.firmware))) or "",
        fontSize = 10,
        color = "on_surface/0.6",
      }),
    }),
    ui.label({
      text = (state and type(state.battery) == "number")
          and (tostring(state.battery) .. "%" .. (state.charging == "charging" and " \u{26a1}" or ""))
        or "",
      fontSize = 15,
      color = connected and xm5.batteryColor(state.battery) or xm5.COLOR_OFF,
      fontWeight = "bold",
    }),
  })

  if not connected then
    kids[#kids + 1] = ui.column({
      gap = 6,
      paddingH = 12,
      paddingV = 12,
      radius = 12,
      fill = xm5.COLOR_LOW .. "1a",
      border = xm5.COLOR_LOW .. "55",
      borderWidth = 1,
      align = "center",
    }, {
      ui.label({ text = "Headphones not connected", fontSize = 12, color = xm5.COLOR_LOW, fontWeight = "medium" }),
      ui.label({
        text = (state and state.error) or "Power on the WH-1000XM5 and refresh.",
        fontSize = 10,
        color = "on_surface/0.7",
        textAlign = "center",
      }),
      ui.button({ text = "Refresh", glyph = "refresh", variant = "primary", controlSize = "sm", onClick = function()
        req("refresh")
      end }),
    })
    return ui.scroll({ key = "scroll", flexGrow = 1 }, {
      ui.column({ key = "root", gap = 12 }, kids),
    })
  end

  -- Noise control ------------------------------------------------------
  if caps().noise then
    local noiseChildren = {
      segment({
        { key = "off", label = "Off" },
        { key = "anc", label = "Noise cancelling" },
        { key = "ambient", label = "Ambient" },
      }, state.noise, function(mode)
        req("noise", { mode = mode })
      end),
    }
    table.insert(noiseChildren, row("Ambient level", ui.label({
      text = tostring(ambientLevel()),
      fontSize = 12,
      color = "on_surface",
      fontWeight = "medium",
    })))
    table.insert(noiseChildren, ui.slider({
      key = "ambient",
      min = 0,
      max = 20,
      step = 1,
      value = ambientLevel(),
      onChange = function(v)
        pending.ambient_level = tonumber(v) or 0
      end,
      onDragEnd = function(v)
        local level = tonumber(v) or ambientLevel()
        pending.ambient_level = nil
        req("ambient-level", { level = level })
      end,
    }))
    table.insert(noiseChildren, row("Focus on Voice", toggle(state.focus_on_voice, function(v)
      req("focus-on-voice", { value = v == "true" })
    end)))
    kids[#kids + 1] = card("Noise control", noiseChildren)
  end

  -- Speak-to-Chat ------------------------------------------------------
  if caps().speak_to_chat then
    kids[#kids + 1] = card(nil, {
      row("Speak-to-Chat", toggle(state.speak_to_chat, function(v)
        req("speak-to-chat", { value = v == "true" })
      end)),
    })
  end

  -- DSEE Extreme -------------------------------------------------------
  if caps().dsee then
    kids[#kids + 1] = card(nil, {
      row("DSEE Extreme", toggle(state.dsee, function(v)
        req("dsee", { value = v == "true" })
      end)),
    })
  end

  -- Connection priority ------------------------------------------------
  if caps().connection then
    local selected = state.connection == "connection_quality" and 1 or 0
    kids[#kids + 1] = card("Connection", {
      row("Priority", ui.select({
        options = { "Sound quality", "Connection quality" },
        selectedIndex = selected,
        controlSize = "sm",
        width = 190,
        onChange = function(idx)
          local i = tonumber(idx) or 0
          req("connection", { mode = i == 1 and "connection_quality" or "sound_quality" })
        end,
      })),
    })
  end

  -- Volume -------------------------------------------------------------
  if caps().volume then
    kids[#kids + 1] = card("Volume", {
      ui.slider({
        key = "volume",
        min = 0,
        max = 100,
        step = 1,
        value = volumeLevel(),
        onChange = function(v)
          pending.volume = tonumber(v) or 0
        end,
        onDragEnd = function(v)
          local level = tonumber(v) or volumeLevel()
          pending.volume = nil
          req("volume", { level = level })
        end,
      }),
    })
  end

  -- Power off ----------------------------------------------------------
  if caps().power_off then
    kids[#kids + 1] = ui.button({
      text = "Power off headphones",
      glyph = "power",
      variant = "destructive",
      flexGrow = 1,
      onClick = function()
        req("power-off")
      end,
    })
  end

  return ui.scroll({ key = "scroll", flexGrow = 1 }, {
    ui.column({ key = "root", gap = 12, paddingV = 4 }, kids),
  })
end

render = function()
  panel.render(buildTree())
end

noctalia.state.watch("xm5", function(value)
  state = value
  pending = {}
  render()
end)

function onOpen()
  state = noctalia.state.get("xm5")
  pending = {}
  render()
  req("refresh")
end

render()
