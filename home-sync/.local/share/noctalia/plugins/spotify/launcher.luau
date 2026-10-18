--!nonstrict
-- Launcher provider for gery/spotify (prefix `/sp`).
--
--   /sp          now playing + transport actions (prev / play-pause / next)
--   /sp lyric    opens the lyrics panel (Spotify-style centred/highlighted view)
--
-- Reads noctalia.state only; actions go through the same `request` channel the
-- widget uses, so the service stays the sole owner of subprocesses.

local function send(action, extra)
  local req = { seq = noctalia.nowMs(), action = action }
  if extra ~= nil then
    for k, v in pairs(extra) do
      req[k] = v
    end
  end
  noctalia.state.set("request", req)
end

function onActivate(id)
  if id == "act:prev" then
    send("previous")
  elseif id == "act:toggle" then
    send("toggle")
  elseif id == "act:next" then
    send("next")
  elseif id == "act:launch" then
    send("launch")
  end
end

function onQuery(text)
  text = text or ""
  if text:match("^%s*[Ll]yric") ~= nil then
    noctalia.togglePanel("gery/spotify:lyrics-panel")
    launcher.setResults(text, {})
    return
  end

  local spotify = noctalia.state.get("spotify") or {}
  local results = {}
  if spotify.active then
    local stateLabel = spotify.playing and noctalia.tr("ui.playing") or noctalia.tr("ui.paused")
    results[#results + 1] = {
      id = "act:launch",
      title = (spotify.title ~= "" and spotify.title) or "Spotify",
      subtitle = spotify.artist ~= "" and (spotify.artist .. " · " .. stateLabel) or stateLabel,
      glyph = "brand-spotify",
    }
    results[#results + 1] = {
      id = "act:prev",
      title = noctalia.tr("ui.previous"),
      glyph = "player-skip-back",
    }
    results[#results + 1] = {
      id = "act:toggle",
      title = spotify.playing and noctalia.tr("ui.pause") or noctalia.tr("ui.play"),
      glyph = spotify.playing and "player-pause" or "player-play",
    }
    results[#results + 1] = {
      id = "act:next",
      title = noctalia.tr("ui.next"),
      glyph = "player-skip-forward",
    }
  else
    results[#results + 1] = {
      id = "act:launch",
      title = noctalia.tr("ui.launcher.open"),
      glyph = "brand-spotify",
    }
  end
  launcher.setResults(text, results)
end
