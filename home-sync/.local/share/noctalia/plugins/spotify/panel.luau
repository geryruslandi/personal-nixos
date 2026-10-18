--!nonstrict
-- Lyrics panel for gery/spotify: a Spotify-style view where the active line is
-- centred and highlighted and the surrounding lines are dimmed, following
-- playback. Opened by the launcher (`/sp lyric`).
--
-- Reads noctalia.state only; transport and seek go through the shared
-- `request` channel so the service stays the sole owner of subprocesses.

-- Rows rendered around the active line. Odd so the active line is the middle
-- row, which `justify = "center"` then keeps vertically centred in the panel.
local WINDOW_ROWS = 11
local HALF = math.floor(WINDOW_ROWS / 2)
-- Long lines wrap (no truncation); must match the panel width minus its
-- horizontal padding (see [[panel]] width in plugin.toml).
local LINE_MAX_WIDTH = 700
local LINE_MAX_LINES = 6

local open = false

local function send(action, extra)
  local req = { seq = noctalia.nowMs(), action = action }
  if extra ~= nil then
    for k, v in pairs(extra) do
      req[k] = v
    end
  end
  noctalia.state.set("request", req)
end

function actPrev()
  send("previous")
end
function actToggle()
  send("toggle")
end
function actNext()
  send("next")
end

local function lyricsRows()
  local lyricsState = noctalia.state.get("lyrics") or {}
  local current = noctalia.state.get("lyric") or {}
  local synced = lyricsState.synced
  local index = current.index
  local rows = {}

  if type(synced) == "table" and #synced > 0 then
    index = index or 1
    for p = 1, WINDOW_ROWS do
      local i = index + (p - (HALF + 1))
      local line = synced[i]
      if line == nil or line.text == "" then
        -- keep the geometry stable near the ends of the song
        rows[#rows + 1] = ui.label({ key = "pad" .. p, text = " ", maxLines = 1 })
      else
        local isActive = (i == index)
        rows[#rows + 1] = ui.row({
          key = "l" .. i,
          align = "center",
          justify = "center",
          padding = 6,
          onClick = function()
            send("seek", { position = line.t or 0 })
          end,
        }, {
          ui.label({
            text = line.text,
            maxWidth = LINE_MAX_WIDTH,
            maxLines = LINE_MAX_LINES,
            textAlign = "center",
            color = isActive and "on_surface" or "on_surface_variant",
            fontWeight = isActive and "bold" or "regular",
            fontSize = isActive and 22 or 20,
          }),
        })
      end
    end
  elseif type(lyricsState.plain) == "string" then
    for line in lyricsState.plain:gmatch("[^\n]+") do
      if line:match("%S") then
        rows[#rows + 1] = ui.label({
          text = line,
          maxWidth = LINE_MAX_WIDTH,
          maxLines = LINE_MAX_LINES,
          textAlign = "center",
          color = "on_surface_variant",
        })
      end
    end
  else
    rows[#rows + 1] = ui.label({
      text = noctalia.tr("ui.launcher.no_lyrics"),
      color = "on_surface_variant",
    })
  end

  return rows
end

local function buildTree()
  local spotify = noctalia.state.get("spotify") or {}
  local playing = spotify.playing == true

  local transport = ui.row({
    gap = 16,
    justify = "center",
    align = "center",
    paddingV = 14,
  }, {
    ui.button({ glyph = "player-skip-back", variant = "ghost", tooltip = noctalia.tr("ui.previous"), onClick = "actPrev" }),
    ui.button({
      glyph = playing and "player-pause" or "player-play",
      variant = "primary",
      tooltip = noctalia.tr(playing and "ui.pause" or "ui.play"),
      onClick = "actToggle",
    }),
    ui.button({ glyph = "player-skip-forward", variant = "ghost", tooltip = noctalia.tr("ui.next"), onClick = "actNext" }),
  })

  -- flexGrow on the root fills the panel height so the lyrics area takes the
  -- slack and the transport sits flush at the very bottom.
  return ui.column({ gap = 0, padding = 0, flexGrow = 1 }, {
    ui.column({ flexGrow = 1, justify = "center", align = "center", gap = 4, paddingH = 28 }, lyricsRows()),
    ui.separator({}),
    transport,
  })
end

local function refresh()
  if open then
    panel.render(buildTree())
  end
end

function onOpen()
  open = true
  panel.render(buildTree())
end

function onClose()
  open = false
end

noctalia.state.watch("lyric", refresh)
noctalia.state.watch("lyrics", refresh)
noctalia.state.watch("spotify", refresh)
