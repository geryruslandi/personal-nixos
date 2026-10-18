--!nonstrict
-- Bar capsule for gery/spotify: the Spotify glyph launches/raises the
-- Spicetify-patched (adblocked) client, the inline buttons drive MPRIS, and the
-- media area toggles between a cava mini-visualizer and the synced lyric line.
-- Reads noctalia.state only — the service owns every subprocess.

local state = { active = false, playing = false, title = "", artist = "", status = "Stopped" }
local viz = {}
local lyric = nil
local mode = noctalia.getConfig("start_mode") == "lyric" and "lyric" or "viz"

-- render values (refreshed from settings each render)
local vizWidth = 56
local vizHeight = 20
local vizColor = "primary"
local lyricWidth = 600

local DEFAULT_BARS = 24
for i = 1, DEFAULT_BARS do
  viz[i] = 0
end

local render -- forward declaration

local function send(action, extra)
  local req = { seq = noctalia.nowMs(), action = action }
  if extra ~= nil then
    for k, v in pairs(extra) do
      req[k] = v
    end
  end
  noctalia.state.set("request", req)
end

-- Named globals (referenced by string in the ui tree) so re-renders reuse them.
function spLaunch()
  send("launch")
end
function spToggle()
  send("toggle")
end
function spNext()
  send("next")
end
function spPrevious()
  send("previous")
end
function spToggleMode()
  mode = (mode == "viz") and "lyric" or "viz"
  noctalia.state.set("uiMode", mode)
  send("mode", { mode = mode })
  render()
end

local function tooltip()
  if state.active and state.title ~= "" then
    local t = state.title
    if state.artist ~= "" then
      t = t .. " — " .. state.artist
    end
    return t
  end
  return noctalia.tr("ui.tooltip")
end

-- The clickable media area: visualizer graph or current lyric line.
local function mediaNode()
  if mode == "lyric" then
    local text = "♪"
    local color = "on_surface_variant"
    -- stretch the capsule while an actual lyric line is shown; keep the
    -- fallback (no lyric) compact
    local width = 180
    if lyric ~= nil and type(lyric.text) == "string" and lyric.text ~= "" then
      text = lyric.text
      color = "on_surface"
      width = lyricWidth
    elseif state.active and state.title ~= "" then
      text = state.title
    end
    return ui.label({ text = text, maxWidth = width, maxLines = 1, color = color })
  end
  return ui.graph({
    values = viz,
    color = vizColor,
    fillOpacity = 0.5,
    width = vizWidth,
    height = vizHeight,
  })
end

render = function()
  local showTitle = noctalia.getConfig("show_title") == true
  local showPrevious = noctalia.getConfig("show_previous") ~= false
  local active = state.active == true
  local playing = state.playing == true

  vizWidth = tonumber(noctalia.getConfig("viz_width")) or 56
  vizHeight = tonumber(noctalia.getConfig("viz_height")) or 20
  vizColor = noctalia.getConfig("viz_color") or "primary"

  local children = {
    ui.button({
      glyph = "brand-spotify",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tooltip(),
      onClick = "spLaunch",
    }),
  }

  if showPrevious then
    children[#children + 1] = ui.button({
      glyph = "player-skip-back",
      variant = "ghost",
      controlSize = "sm",
      enabled = active,
      tooltip = noctalia.tr("ui.previous"),
      onClick = "spPrevious",
    })
  end

  children[#children + 1] = ui.button({
    glyph = playing and "player-pause" or "player-play",
    variant = "ghost",
    controlSize = "sm",
    enabled = active,
    tooltip = noctalia.tr(playing and "ui.pause" or "ui.play"),
    onClick = "spToggle",
  })

  children[#children + 1] = ui.button({
    glyph = "player-skip-forward",
    variant = "ghost",
    controlSize = "sm",
    enabled = active,
    tooltip = noctalia.tr("ui.next"),
    onClick = "spNext",
  })

  -- Media area: click toggles visualizer <-> lyrics.
  children[#children + 1] = ui.row({
    gap = 0,
    padding = 0,
    align = "center",
    onClick = "spToggleMode",
  }, { mediaNode() })

  if showTitle and active and state.title ~= "" then
    local text = state.title
    if state.artist ~= "" then
      text = text .. " — " .. state.artist
    end
    children[#children + 1] = ui.label({
      text = text,
      maxWidth = 160,
      maxLines = 1,
      color = "on_surface_variant",
    })
  end

  local props = { gap = 0, padding = 0, align = "center" }
  if barWidget.isVertical() then
    barWidget.render(ui.column(props, children))
  else
    barWidget.render(ui.row(props, children))
  end
end

noctalia.state.watch("spotify", function(value)
  if type(value) == "table" then
    state = value
  end
  render()
end)

noctalia.state.watch("viz", function(value)
  if type(value) == "table" and #value > 0 then
    viz = value
  end
  if mode == "viz" then
    render()
  end
end)

noctalia.state.watch("lyric", function(value)
  lyric = value
  if mode == "lyric" then
    render()
  end
end)

function update()
  local s = noctalia.state.get("spotify")
  if type(s) == "table" then
    state = s
  end
  local v = noctalia.state.get("viz")
  if type(v) == "table" and #v > 0 then
    viz = v
  end
  local l = noctalia.state.get("lyric")
  if l ~= nil then
    lyric = l
  end
  render()
end

-- Publish the starting mode for the service (it reconciles via "uiMode") and
-- ask for freshness right away.
noctalia.state.set("uiMode", mode)
send("mode", { mode = mode })
noctalia.setUpdateInterval(2000)
render()
