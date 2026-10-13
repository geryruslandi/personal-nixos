--!nonstrict

local PANEL_ID = "gery/mini-docker:manager"

-- Status palette shared with the gery/services hub so the Docker icon and the
-- running counter read the same at a glance: green = running, red = stopped,
-- gray = unavailable.
local COLOR_RUNNING = "#4ade80"
local COLOR_STOPPED = "#f87171"
local COLOR_MISSING = "#64748b"

local snapshot = noctalia.state.get("docker_snapshot") or {
  available = false,
  loading = true,
  runningCount = 0,
}
local requestId = 0

local function configString(key, fallback)
  local value = noctalia.getConfig(key)
  return type(value) == "string" and value or fallback
end

local function render()
  local runningCount = tonumber(snapshot.runningCount) or 0
  local available = snapshot.available == true
  local showCount = noctalia.getConfig("show_count") ~= false
  local statusMode = configString("status_mode", "always")
  local showStatus = available
    and statusMode ~= "hidden"
    and (statusMode ~= "running_only" or runningCount > 0)

  local color
  if not available then
    color = COLOR_MISSING
  elseif runningCount > 0 then
    color = COLOR_RUNNING
  else
    color = COLOR_STOPPED
  end

  local children = {
    ui.glyph({
      name = "brand-docker",
      size = 16,
      color = color,
    }),
  }
  if showCount and available then
    table.insert(children, ui.label({
      text = tostring(runningCount),
      fontWeight = "bold",
      color = color,
    }))
  end
  if showStatus then
    table.insert(children, ui.box({
      width = 7,
      height = 7,
      radius = 4,
      fill = color,
    }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center" }, children))
  barWidget.setTooltip(if available
    then noctalia.tr("widget.running", { count = runningCount })
    else noctalia.tr("widget.unavailable"))
end

noctalia.state.watch("docker_snapshot", function(value)
  if type(value) == "table" then
    snapshot = value
    render()
  end
end)

noctalia.setUpdateInterval(5000)
render()

function update()
  render()
end

function onClick()
  if snapshot.available == true then
    noctalia.togglePanel(PANEL_ID)
  else
    noctalia.notifyError(noctalia.tr("title"), snapshot.error or noctalia.tr("widget.unavailable"))
  end
end

function onRightClick()
  requestId += 1
  noctalia.state.set("docker_command", { action = "refresh", requestId = `widget-{requestId}` })
  noctalia.notify(noctalia.tr("title"), noctalia.tr("widget.refresh_requested"))
end
