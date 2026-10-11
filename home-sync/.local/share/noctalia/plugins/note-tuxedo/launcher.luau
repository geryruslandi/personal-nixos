--!nonstrict
-- Launcher provider behind `/t`. Free text offers a quick `add`; matching
-- pending tasks offer to complete/uncomplete. Reads noctalia.state only.

local note = require("./lib/note.luau")

local lastQuery = ""

local function send(tbl)
  tbl.seq = noctalia.nowMs()
  noctalia.state.set("request", tbl)
end

local function subtitle(t)
  local parts = {}
  if t.priority ~= nil and t.priority ~= "" then
    parts[#parts + 1] = noctalia.tr("ui.priority", { p = t.priority })
  end
  if t.due ~= nil and t.due ~= "" then parts[#parts + 1] = t.due end
  for _, p in ipairs(t.projects) do parts[#parts + 1] = "+" .. p end
  for _, c in ipairs(t.contexts) do parts[#parts + 1] = "@" .. c end
  return table.concat(parts, " · ")
end

function onQuery(text)
  lastQuery = text or ""
  local q = note.trim(lastQuery)
  local results = {}

  if q ~= "" then
    results[#results + 1] = {
      id = "add",
      title = noctalia.tr("ui.launcher.add", { text = q }),
      subtitle = noctalia.tr("ui.launcher.add_sub"),
      glyph = "plus",
      score = 1000,
    }

    local all = noctalia.state.get("tasks")
    if type(all) == "table" then
      local needle = q:lower()
      local matched = 0
      for _, t in ipairs(all) do
        if not t.done and t.raw:lower():find(needle, 1, true) then
          matched = matched + 1
          results[#results + 1] = {
            id = "task:" .. tostring(t.n),
            title = t.raw,
            subtitle = subtitle(t),
            glyph = "list-check",
            score = 500 - matched,
          }
          if matched >= 8 then break end
        end
      end
    end
  end

  launcher.setResults(lastQuery, results)
end

function onActivate(id)
  if id == "add" then
    local q = note.trim(lastQuery)
    if q ~= "" then send({ action = "add", text = q }) end
  elseif type(id) == "string" then
    local n = tonumber(id:match("^task:(%d+)$"))
    if n ~= nil then send({ action = "toggle", n = n }) end
  end
end
