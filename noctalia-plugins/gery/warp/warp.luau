noctalia.setUpdateInterval(5000)

local WARP = "warp-cli"
local DAEMON = "cloudflare-warp.service"

local state = "unknown"

local function render()
  if state == "no-cli" then
    barWidget.setGlyph("alert-triangle")
    barWidget.setText("warp-cli not installed")
    barWidget.setTooltip("warp-cli not installed\nInstall the cloudflare-warp package to use this toggle.")
  elseif state == "daemon-off" then
    barWidget.setGlyph("shield-off")
    barWidget.setText("WARP")
    barWidget.setTooltip("Cloudflare WARP daemon is stopped\nStart it with: systemctl start cloudflare-warp.service")
  elseif state == "not-setup" then
    barWidget.setGlyph("shield-x")
    barWidget.setText("warp-cli not setup")
    barWidget.setTooltip("warp-cli not setup\nRun: sudo warp-cli registration new")
  elseif state == "connected" then
    barWidget.setGlyph("shield-check")
    barWidget.setText("WARP")
    barWidget.setTooltip("Cloudflare WARP: connected\nClick to disconnect")
  else
    barWidget.setGlyph("shield-off")
    barWidget.setText("WARP")
    barWidget.setTooltip("Cloudflare WARP: disconnected\nClick to connect")
  end
end

local function pollStatus()
  local ok = noctalia.runAsync(WARP .. " status", function(res)
    local out = res and res.stdout or ""
    if out:find("Connected", 1, true) then
      state = "connected"
    else
      state = "disconnected"
    end
    render()
  end)
  if not ok then
    state = "error"
    render()
  end
end

local function pollRegistration()
  local ok = noctalia.runAsync(WARP .. " registration show", function(res)
    if res and res.exitCode == 0 then
      pollStatus()
    else
      state = "not-setup"
      render()
    end
  end)
  if not ok then
    state = "not-setup"
    render()
  end
end

local function pollDaemon()
  local ok = noctalia.runAsync("systemctl is-active " .. DAEMON, function(res)
    local out = res and res.stdout or ""
    if out:find("active", 1, true) then
      pollRegistration()
    else
      state = "daemon-off"
      render()
    end
  end)
  if not ok then
    state = "daemon-off"
    render()
  end
end

local function refresh()
  if not noctalia.commandExists(WARP) then
    state = "no-cli"
    render()
    return
  end
  pollDaemon()
end

local function afterToggle()
  refresh()
end

function update()
  refresh()
end

function onClick()
  if state == "connected" then
    noctalia.runAsync(WARP .. " disconnect", afterToggle)
  elseif state == "disconnected" then
    noctalia.runAsync(WARP .. " connect", afterToggle)
  elseif state == "no-cli" then
    noctalia.notify("warp-cli not installed", "Install the cloudflare-warp package to use this toggle.")
  elseif state == "not-setup" then
    noctalia.notify("warp-cli not setup", "Run: sudo warp-cli registration new")
  elseif state == "daemon-off" then
    noctalia.notify("WARP daemon stopped", "Start it with: systemctl start cloudflare-warp.service")
  end
end
