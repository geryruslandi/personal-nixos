--!nonstrict
-- Password / passphrase generator panel (Raycast's Generate Password form):
-- current value as preview, options, Copy / Paste / Regenerate. The last used
-- options persist in the plugin data dir, layered over the plugin settings.

local cfg = require("./lib/cfg.luau")
local rpc = require("./lib/rpc.luau")

rpc.init()

local opts = nil
local value = nil
local busy = false
local errorText = nil
local frameAcc = 0

local render -- forward

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

local function optionsFile()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" then
    return nil
  end
  return dir .. "/generator.json"
end

local function loadOptions()
  opts = cfg.generatorDefaults()
  local path = optionsFile()
  if path == nil then
    return
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" then
    return
  end
  local saved = noctalia.json.decode(raw)
  if type(saved) ~= "table" then
    return
  end
  if saved.mode == "passphrase" or saved.mode == "password" then
    opts.mode = saved.mode
  end
  if type(saved.length) == "number" then
    opts.length = cfg.clampLength(saved.length)
  end
  if type(saved.words) == "number" then
    opts.words = cfg.clampWords(saved.words)
  end
  if type(saved.separator) == "string" then
    opts.separator = saved.separator
  end
  for _, key in ipairs({ "upper", "lower", "number", "special", "capitalize", "includeNumber" }) do
    if type(saved[key]) == "boolean" then
      opts[key] = saved[key]
    end
  end
end

local function saveOptions()
  local path = optionsFile()
  if path == nil or opts == nil then
    return
  end
  noctalia.writeFile(path, noctalia.json.encode(opts) or "{}")
end

local function generate()
  if busy or opts == nil then
    return
  end
  busy = true
  errorText = nil
  panel.setNeedsFrameTick(true)
  rpc.send("generate", { opts = opts }, function(ok, data, err)
    busy = false
    if ok and type(data) == "table" then
      value = data.value
    else
      errorText = err or tr("gen.failed")
    end
    render()
  end)
end

local function copyValue()
  if value == nil then
    return
  end
  rpc.notify("copy-value", { value = value, label = tr("gen.generated"), sensitive = true })
end

local function pasteValue()
  if value == nil then
    return
  end
  rpc.notify("paste-value", { value = value, label = tr("gen.generated"), sensitive = true })
end

local function section(title, control)
  return ui.column({ gap = 6, align = "stretch" }, {
    ui.label({ text = title, fontWeight = "medium", color = "on_surface_variant" }),
    control,
  })
end

local function toggleRow(title, key)
  return ui.row({ gap = 10, align = "center" }, {
    ui.toggle({
      checked = opts[key],
      onChange = function(v)
        opts[key] = v == "true"
        saveOptions()
        generate()
        render()
      end,
    }),
    ui.label({ text = title, flexGrow = 1 }),
  })
end

render = function()
  if opts == nil then
    panel.render(ui.column({}, { ui.label({ text = tr("gen.generating") }) }))
    return
  end
  local isPassphrase = opts.mode == "passphrase"
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = tr("gen.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = function()
        panel.close()
      end }),
    }),
    ui.column({ fill = "surface_variant/0.5", radius = 10, padding = 12, align = "center" }, {
      ui.label({
        text = value or (busy and tr("gen.generating") or tr("gen.empty")),
        fontSize = 16,
        fontWeight = "bold",
        maxLines = 4,
        textAlign = "center",
      }),
    }),
    ui.row({ gap = 8 }, {
      ui.button({ text = tr("gen.copy"), variant = "primary", flexGrow = 1, enabled = value ~= nil, onClick = copyValue }),
      ui.button({ text = tr("gen.paste"), flexGrow = 1, enabled = value ~= nil, onClick = pasteValue }),
      ui.button({ text = tr("gen.regenerate"), glyph = "refresh", flexGrow = 1, enabled = not busy, onClick = generate }),
    }),
    ui.separator({}),
    section(tr("gen.type"), ui.select({
      options = { tr("gen.password"), tr("gen.passphrase") },
      selectedIndex = isPassphrase and 1 or 0,
      onChange = function(index)
        opts.mode = tonumber(index) == 1 and "passphrase" or "password"
        saveOptions()
        generate()
        render()
      end,
    })),
  }
  if isPassphrase then
    table.insert(children, section(
      tr("gen.words", { count = tostring(opts.words) }),
      ui.slider({
        min = 3,
        max = 20,
        step = 1,
        value = opts.words,
        onDragEnd = function(v)
          opts.words = cfg.clampWords(tonumber(v))
          saveOptions()
          generate()
          render()
        end,
      })
    ))
    table.insert(children, section(tr("gen.separator"), ui.input({
      key = "separator",
      value = opts.separator,
      onChange = function(v)
        opts.separator = v
      end,
      onSubmit = function(v)
        opts.separator = v
        saveOptions()
        generate()
        render()
      end,
    })))
    table.insert(children, toggleRow(tr("gen.capitalize"), "capitalize"))
    table.insert(children, toggleRow(tr("gen.include-number"), "includeNumber"))
  else
    table.insert(children, section(
      tr("gen.length", { count = tostring(opts.length) }),
      ui.slider({
        min = 5,
        max = 128,
        step = 1,
        value = opts.length,
        onDragEnd = function(v)
          opts.length = cfg.clampLength(tonumber(v))
          saveOptions()
          generate()
          render()
        end,
      })
    ))
    table.insert(children, toggleRow(tr("gen.uppercase"), "upper"))
    table.insert(children, toggleRow(tr("gen.lowercase"), "lower"))
    table.insert(children, toggleRow(tr("gen.numbers"), "number"))
    table.insert(children, toggleRow(tr("gen.specials"), "special"))
  end
  if errorText ~= nil then
    table.insert(children, ui.label({ text = errorText, color = "error", maxLines = 3 }))
  end
  panel.render(ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

function onOpen(_context)
  loadOptions()
  value = nil
  busy = false
  errorText = nil
  render()
  generate()
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
