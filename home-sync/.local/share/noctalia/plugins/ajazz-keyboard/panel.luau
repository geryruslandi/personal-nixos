--!nonstrict
local ak = require("./lib/ak820.luau")

local open = false
local status = nil
local panel_cfg = ak.load_panel()
local hex_text = panel_cfg.color
local disk_text = panel_cfg.disk_path
local hex_seed = 0
local disk_seed = 0
local due = 0

local render

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function apply()
  due = 0
  panel.setNeedsFrameTick(false)
  ak.request("config", { config = panel_cfg })
end

local function schedule(delay)
  due = noctalia.nowMs() + (delay or 180)
  panel.setNeedsFrameTick(true)
end

local function set_color(value)
  local effect = panel_cfg.effect == "off" and "static" or panel_cfg.effect
  panel_cfg = ak.normalize_panel(ak.merge(panel_cfg, { color = value, effect = effect }))
  hex_text = panel_cfg.color
  hex_seed = hex_seed + 1
  render()
  apply()
end

local function selected_button(key, label, selected, on_click)
  return ui.button({
    key = key,
    text = label,
    variant = selected and "primary" or "outline",
    selected = selected,
    controlSize = "sm",
    onClick = on_click,
  })
end

local function stat_row(label, value)
  return ui.row({
    key = "stat-" .. label,
    justify = "space_between",
    align = "center",
    paddingV = 1,
  }, {
    ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
    ui.label({ text = value, fontSize = 11, color = "on_surface" }),
  })
end

local function color_slider(label, value, on_change)
  return ui.row({
    key = "color-" .. label,
    gap = 8,
    align = "center",
  }, {
    ui.label({ text = label, fontSize = 11, width = 16, color = "on_surface_variant" }),
    ui.slider({
      key = "color-slider-" .. label,
      min = 0,
      max = 255,
      step = 1,
      value = value,
      flexGrow = 1,
      onChange = function(raw)
        on_change(ak.clamp_int(tonumber(raw) or 0, 0, 255, 0))
      end,
    }),
    ui.label({ text = tostring(value), fontSize = 11, width = 34, textAlign = "end", color = "on_surface_variant" }),
  })
end

local function value_slider(key, label, value, low, high, on_change)
  return ui.row({ key = key, gap = 8, align = "center" }, {
    ui.label({ text = label, fontSize = 11, width = 76, color = "on_surface_variant" }),
    ui.slider({
      key = key .. "-slider",
      min = low,
      max = high,
      step = 1,
      value = value,
      flexGrow = 1,
      onChange = function(raw)
        on_change(ak.clamp_int(tonumber(raw) or low, low, high, low))
      end,
    }),
    ui.label({ text = tostring(value), fontSize = 11, width = 24, textAlign = "end", color = "on_surface_variant" }),
  })
end

local function device_section()
  local connected = status ~= nil and status.connected == true
  local label = connected and tr("ui.widget.connected") or tr("ui.widget.disconnected")
  if status ~= nil and status.error ~= nil then
    label = label .. " · " .. tostring(status.error)
  end
  local detail = "—"
  if status ~= nil and status.path ~= nil then
    detail = tostring(status.path)
    if status.pid ~= nil and status.pid ~= "" then
      detail = detail .. "  ·  " .. tostring(status.pid)
    end
  end
  return ui.column({ gap = 6 }, {
    ui.row({ align = "center", justify = "space_between" }, {
      ui.column({ gap = 1 }, {
        ui.label({ text = tr("ui.title"), fontSize = 16, fontWeight = "bold" }),
        ui.label({ text = tr("ui.subtitle"), fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.button({
        text = tr("ui.reconnect"),
        glyph = "refresh",
        variant = "outline",
        controlSize = "sm",
        onClick = function()
          ak.request("reconnect")
        end,
      }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({
        name = connected and "plug" or "plug-off",
        size = 14,
        color = connected and "primary" or "on_surface_variant",
      }),
      ui.label({ text = label, fontSize = 11, color = connected and "primary" or "on_surface_variant", maxLines = 2 }),
    }),
    ui.label({ text = detail, fontSize = 10, color = "on_surface_variant" }),
  })
end

local function lighting_section()
  local effect_buttons = {}
  for _, effect in ipairs(ak.EFFECTS) do
    effect_buttons[#effect_buttons + 1] = selected_button(
      "effect-" .. effect,
      tr("ui.effect." .. effect),
      panel_cfg.effect == effect,
      function()
        panel_cfg = ak.normalize_panel(ak.merge(panel_cfg, { effect = effect }))
        render()
        apply()
      end
    )
  end

  local red, green, blue = ak.hex_to_rgb(panel_cfg.color)
  local preset_nodes = {}
  for _, preset in ipairs(ak.PRESETS) do
    preset_nodes[#preset_nodes + 1] = ui.box({
      key = "preset-" .. preset.name,
      width = 22,
      height = 22,
      radius = 6,
      fill = preset.color,
      border = "outline",
      borderWidth = 1,
      onClick = function()
        set_color(preset.color)
      end,
    })
  end

  return ui.column({ gap = 8 }, {
    ui.label({ text = tr("ui.lighting"), fontSize = 12, color = "primary", fontWeight = "bold" }),
    ui.row({ gap = 6 }, effect_buttons),
    ui.row({ gap = 10, align = "center" }, {
      ui.box({ width = 34, height = 34, radius = 8, fill = panel_cfg.color, border = "outline", borderWidth = 1 }),
      ui.input({
        key = "hex-" .. hex_seed,
        value = hex_text,
        placeholder = "#89b4fa",
        width = 150,
        onSubmit = function(value)
          set_color(value)
        end,
        onChange = function(value)
          hex_text = value
        end,
      }),
      ui.button({
        text = tr("ui.color.apply"),
        controlSize = "sm",
        variant = "secondary",
        onClick = function()
          set_color(hex_text)
        end,
      }),
    }),
    ui.row({ gap = 6, align = "center" }, preset_nodes),
    color_slider("R", red, function(value)
      local _, g, b = ak.hex_to_rgb(panel_cfg.color)
      if panel_cfg.effect == "off" then panel_cfg.effect = "static" end
      panel_cfg.color = ak.rgb_to_hex(value, g, b)
      hex_text = panel_cfg.color
      schedule()
    end),
    color_slider("G", green, function(value)
      local r, _, b = ak.hex_to_rgb(panel_cfg.color)
      if panel_cfg.effect == "off" then panel_cfg.effect = "static" end
      panel_cfg.color = ak.rgb_to_hex(r, value, b)
      hex_text = panel_cfg.color
      schedule()
    end),
    color_slider("B", blue, function(value)
      local r, g, _ = ak.hex_to_rgb(panel_cfg.color)
      if panel_cfg.effect == "off" then panel_cfg.effect = "static" end
      panel_cfg.color = ak.rgb_to_hex(r, g, value)
      hex_text = panel_cfg.color
      schedule()
    end),
    value_slider("brightness", tr("ui.brightness"), panel_cfg.brightness, 0, 4, function(value)
      panel_cfg.brightness = value
      schedule()
    end),
    value_slider("speed", tr("ui.speed"), panel_cfg.speed, 0, 4, function(value)
      panel_cfg.speed = value
      schedule()
    end),
  })
end

local function screen_section()
  local mode_buttons = {}
  for _, mode in ipairs(ak.SCREENS) do
    mode_buttons[#mode_buttons + 1] = selected_button(
      "screen-" .. mode,
      tr("ui.screen." .. mode),
      panel_cfg.screen == mode,
      function()
        panel_cfg = ak.normalize_panel(ak.merge(panel_cfg, { screen = mode }))
        render()
        apply()
      end
    )
  end

  local language_buttons = {}
  for _, language in ipairs(ak.LANGUAGES) do
    language_buttons[#language_buttons + 1] = selected_button(
      "language-" .. language,
      tr("ui.language." .. language),
      panel_cfg.language == language,
      function()
        panel_cfg = ak.normalize_panel(ak.merge(panel_cfg, { language = language }))
        render()
        apply()
      end
    )
  end

  local clock_labels = {
    tr("ui.clock.1m"),
    tr("ui.clock.5m"),
    tr("ui.clock.15m"),
    tr("ui.clock.30m"),
    tr("ui.clock.1h"),
  }
  local clock_index = 1
  for index, value in ipairs(ak.CLOCK_INTERVALS) do
    if value == panel_cfg.clock_interval_s then
      clock_index = index - 1
      break
    end
  end

  local stats_labels = {}
  for index, value in ipairs(ak.STATS_INTERVALS) do
    stats_labels[index] = tostring(value) .. " s"
  end
  local stats_index = 0
  for index, value in ipairs(ak.STATS_INTERVALS) do
    if value == panel_cfg.stats_interval_s then
      stats_index = index - 1
      break
    end
  end

  local stats_rows = {}
  local stats = status ~= nil and status.stats or nil
  if type(stats) == "table" then
    stats_rows[#stats_rows + 1] = stat_row("CPU", tostring(stats.cpu_usage or 0) .. " %")
    stats_rows[#stats_rows + 1] = stat_row(tr("ui.stats.temp"), tostring(stats.cpu_temp or 0) .. " °C")
    stats_rows[#stats_rows + 1] = stat_row(
      "RAM",
      string.format("%d / %d GB", stats.mem_used_gb or 0, stats.mem_total_gb or 0)
    )
    stats_rows[#stats_rows + 1] = stat_row(
      tr("ui.stats.disk_short"),
      string.format(
        "%d / %d GB",
        (stats.disk_total_gb or 0) - (stats.disk_available_gb or 0),
        stats.disk_total_gb or 0
      )
    )
    local unit = panel_cfg.net_mode == "total" and "KB" or "KB/s"
    stats_rows[#stats_rows + 1] = stat_row(
      tr("ui.stats.net_short"),
      string.format("↑%d ↓%d %s", stats.net_up_kb or 0, stats.net_down_kb or 0, unit)
    )
  else
    stats_rows[#stats_rows + 1] = ui.label({ text = tr("ui.stats.no_data"), fontSize = 11, color = "on_surface_variant" })
  end

  return ui.column({ gap = 8 }, {
    ui.label({ text = tr("ui.screen"), fontSize = 12, color = "primary", fontWeight = "bold" }),
    ui.row({ gap = 6 }, mode_buttons),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = tr("ui.screen.language"), fontSize = 11, color = "on_surface_variant", width = 120 }),
      ui.row({ gap = 4 }, language_buttons),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = tr("ui.clock.sync"), fontSize = 11, color = "on_surface_variant", width = 160 }),
      ui.toggle({
        checked = panel_cfg.clock_enabled,
        onChange = function(raw)
          panel_cfg.clock_enabled = raw == true or raw == "true"
          schedule(0)
        end,
      }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = tr("ui.clock.interval"), fontSize = 11, color = "on_surface_variant", width = 120 }),
      ui.select({
        options = clock_labels,
        selectedIndex = clock_index,
        width = 150,
        onChange = function(index)
          local selected = tonumber(index) + 1
          panel_cfg.clock_interval_s = ak.CLOCK_INTERVALS[selected] or 300
          schedule(0)
        end,
      }),
      ui.button({
        text = tr("ui.clock.now"),
        controlSize = "sm",
        variant = "secondary",
        onClick = function()
          ak.request("clock_sync")
        end,
      }),
    }),
    ui.column({ gap = 6, visible = panel_cfg.screen == "cpu" }, {
      ui.separator({}),
      ui.label({ text = tr("ui.stats"), fontSize = 12, color = "primary", fontWeight = "bold" }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("ui.stats.interval"), fontSize = 11, color = "on_surface_variant", width = 120 }),
        ui.select({
          options = stats_labels,
          selectedIndex = stats_index,
          width = 150,
          onChange = function(index)
            local selected = tonumber(index) + 1
            panel_cfg.stats_interval_s = ak.STATS_INTERVALS[selected] or 1
            schedule(0)
          end,
        }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("ui.stats.disk"), fontSize = 11, color = "on_surface_variant", width = 120 }),
        ui.input({
          key = "disk-" .. disk_seed,
          value = disk_text,
          width = 180,
          onSubmit = function(value)
            panel_cfg.disk_path = value ~= "" and value or "/"
            schedule(0)
          end,
          onChange = function(value)
            disk_text = value
          end,
        }),
        ui.button({
          text = tr("ui.apply"),
          controlSize = "sm",
          variant = "secondary",
          onClick = function()
            panel_cfg.disk_path = disk_text ~= "" and disk_text or "/"
            schedule(0)
          end,
        }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("ui.stats.net"), fontSize = 11, color = "on_surface_variant", width = 120 }),
        ui.select({
          options = { tr("ui.stats.net.rate"), tr("ui.stats.net.total") },
          selectedIndex = panel_cfg.net_mode == "total" and 1 or 0,
          width = 180,
          onChange = function(index)
            panel_cfg.net_mode = tonumber(index) == 1 and "total" or "rate"
            schedule(0)
          end,
        }),
      }),
      ui.column({ gap = 2, paddingV = 4 }, stats_rows),
    }),
  })
end

local function footer_section()
  return ui.row({ align = "center", justify = "space_between" }, {
    ui.label({ text = tr("ui.footer"), fontSize = 10, color = "on_surface_variant" }),
    ui.button({
      text = tr("ui.reset"),
      variant = "destructive",
      controlSize = "sm",
      onClick = function()
        ak.request("reset")
      end,
    }),
  })
end

local function build_tree()
  return ui.scroll({ key = "scroll", flexGrow = 1 }, {
    ui.column({ gap = 14, padding = 16 }, {
      device_section(),
      ui.separator({}),
      lighting_section(),
      ui.separator({}),
      screen_section(),
      ui.separator({}),
      footer_section(),
    }),
  })
end

render = function()
  panel.render(build_tree())
end

function onFrameTick()
  if due > 0 and noctalia.nowMs() >= due then
    render()
    apply()
  end
end

function onOpen()
  noctalia.log("ajazz panel opened")
  open = true
  noctalia.state.set("panelOpen", true)
  due = 0
  local value = noctalia.state.get("ak820")
  status = value
  if value ~= nil and type(value.panel) == "table" then
    panel_cfg = ak.normalize_panel(value.panel)
  else
    panel_cfg = ak.load_panel()
  end
  hex_text = panel_cfg.color
  disk_text = panel_cfg.disk_path
  hex_seed = hex_seed + 1
  disk_seed = disk_seed + 1
  render()
end

function onClose()
  noctalia.log("ajazz panel closed")
  open = false
  noctalia.state.set("panelOpen", false)
  due = 0
  panel.setNeedsFrameTick(false)
end

noctalia.state.watch("ak820", function(value)
  status = value
  if open and due == 0 and value ~= nil and type(value.panel) == "table" then
    local next_panel = ak.normalize_panel(value.panel)
    if next_panel.color ~= panel_cfg.color then
      hex_seed = hex_seed + 1
    end
    if next_panel.disk_path ~= panel_cfg.disk_path then
      disk_seed = disk_seed + 1
    end
    panel_cfg = next_panel
    hex_text = panel_cfg.color
    disk_text = panel_cfg.disk_path
    render()
  end
end)
