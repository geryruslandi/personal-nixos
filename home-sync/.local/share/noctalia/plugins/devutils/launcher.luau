--!nonstrict
-- Launcher provider for gery/devutils (prefix /dev).
-- Lists the four tools; activating one opens the panel on that tab.

local TOOLS = {
  { id = "json",     titleKey = "tool.json.title",     subtitleKey = "tool.json.subtitle",     glyph = "brackets" },
  { id = "sql",      titleKey = "tool.sql.title",      subtitleKey = "tool.sql.subtitle",      glyph = "database" },
  { id = "markdown", titleKey = "tool.markdown.title", subtitleKey = "tool.markdown.subtitle", glyph = "markdown" },
  { id = "php",      titleKey = "tool.php.title",      subtitleKey = "tool.php.subtitle",      glyph = "brand-php" },
}

function onActivate(id)
  local tool = string.match(id or "", "^tool:(.+)$")
  if tool == nil then return end
  noctalia.state.set("openTool", tool)
  noctalia.togglePanel("gery/devutils:devutils-panel")
end

function onQuery(text)
  text = text or ""
  local results = {}
  for _, t in ipairs(TOOLS) do
    local title = noctalia.tr(t.titleKey)
    local subtitle = noctalia.tr(t.subtitleKey)
    local included = text:match("^%s*$") ~= nil
    if not included then
      local s1 = noctalia.fuzzyScore(text, title)
      local s2 = noctalia.fuzzyScore(text, subtitle)
      if s1 ~= nil or s2 ~= nil then included = true end
    end
    if included then
      results[#results + 1] = {
        id = "tool:" .. t.id,
        title = title,
        subtitle = subtitle,
        glyph = t.glyph,
      }
    end
  end
  launcher.setResults(text, results)
end
