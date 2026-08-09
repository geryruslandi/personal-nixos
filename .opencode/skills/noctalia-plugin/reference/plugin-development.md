# Noctalia v5 Plugin Development — Full Reference

Distilled from `docs.noctalia.dev/noctalia/plugins/development/` (Overview, Manifest & Settings, Entry Scripts, Declarative UI, Runtime API, Plugin API Versions, Workflow & Publishing). **The plugin system is beta — APIs may still change.**

A plugin is a directory with a static `plugin.toml` manifest and one or more Luau entry scripts. Each entry runs in its own isolated VM off the UI thread with per-call time budgets. Plugins are **trusted code** (installing one = running a user-owned script). An entry is addressed `<author>/<plugin>:<entry-id>`.

---

## 1. Manifest (`plugin.toml`)

### Root fields

```toml
id           = "me/hello" # "<author>/<plugin>" - globally unique
name         = "Hello"    # REQUIRED
version      = "1.0.0"
plugin_api   = 3          # REQUIRED, positive int, oldest API level needed (3-23)
author       = "me"
license      = "MIT"      # optional; defaults to MIT
deprecated   = false      # optional; soft status marker
icon         = "puzzle"   # optional
description  = "A friendly greeter."
tags         = ["demo"]   # optional, catalog search
dependencies = ["slurp"]  # optional metadata, does not block enabling
```

`name` and `plugin_api` are required — a manifest without either is rejected. `plugin_api` gates enable, catalog badge, and update safety; levels are cumulative (leave it unchanged until you adopt a newer capability).

### Entry kinds

| `[[kind]]` | Runs as | Addressed |
|---|---|---|
| `[[widget]]` | Bar widget; ticks + clicks/IPC | `type = "<author>/<plugin>:<id>"` |
| `[[shortcut]]` | Control-center toggle tile | `type = "<author>/<plugin>:<id>"` in `control_center.shortcuts` |
| `[[launcher_provider]]` | Launcher results behind a prefix | prefix key in launcher `/` overview |
| `[[desktop_widget]]` | Tile on desktop; `ui.*` tree | placement in desktop-widgets editor |
| `[[panel]]` | Pop-up surface; `ui.*` tree, opened by id | `noctalia msg panel-toggle <author>/<plugin>:<id>` |
| `[[service]]` | Headless loop feeding the plugin | `all` target only |

```toml
[[widget]]
id    = "hello"
entry = "widget.luau"

  [[widget.setting]]
  key     = "label"
  type    = "string"
  label   = "Label"   # ILLEGAL — labels are translation keys
  label_key = "settings.label.label"
  default = "Hello"

[[service]]
id    = "ticker"
entry = "ticker.luau"
```

### Widget gesture defaults (`plugin_api = 14`)

A `[widget.actions]` table declares click/scroll defaults shown in the settings editor. A binding takes precedence over the script — bind `right` and `onRightClick` stops firing. Gestures not declared and not bound still reach callbacks.

```toml
[[widget]]
id    = "hello"
entry = "widget.luau"

  [widget.actions]
  right      = "media toggle"
  scroll_up  = "volume-up"
```

Middle click: every widget gets a built-in `middle` binding opening its settings, so `onMiddleClick` doesn't fire unless `middle = "none"` frees it. See `noctalia/bar/actions/` for the gesture keys and action grammar.

### Settings schema

Two scopes, same field schema:

- **Plugin-level** `[[setting]]` at the manifest root — shared by every entry, edited under **Settings → Plugins** (gear on the plugin row).
- **Entry-level** `[[widget.setting]]` / `[[panel.setting]]` — per widget instance (edited with the widget's own settings) or plugin-row gear for panels.
- When both declare the same key, the widget entry value wins for that widget.

Field schema:

| Field | Notes |
|---|---|
| `key` | **required**; the config key read via `noctalia.getConfig(key)` |
| `type` | `string`, `string_list`, `string_map` (API 6), `bool`, `int`, `double`, `select`, `file`, `folder`, `glyph`, `color` |
| `label_key` | **required**; translation key for the settings-GUI label |
| `description_key` | optional; translation key |
| `default` | seeded value, must match type |
| `min` / `max` | for `int` / `double` |
| `options` | for `select`: array of `{ value, label_key }`; both required |
| `extensions` | optional array for `file`, e.g. `[".toml", ".json"]`; empty = any file |
| `visible_when` | `{ key = "other_key", values = ["true"] }` conditional visibility |
| `advanced` | hide behind the "show advanced" toggle |

`file`/`folder` store strings, rendered as text input + browse button. `string_map` (API 6) returns an associative Luau table; its default is a TOML table and it is configured with a subtable.

Labels/descriptions are **always translation keys** — literal `label`/`description` rejected. Text lives in the same `translations/<lang>.json` as script strings; a plugin with settings needs at least `translations/en.json`:

```json
{
  "settings.interval.label": "Refresh seconds",
  "settings.interval.description": "How often the service refreshes data."
}
```

Multiple named widget instances can share one entry with different widget settings:
```toml
[widget.hello-main]
type  = "me/hello:hello"
label = "Main"

[widget.hello-short]
type  = "me/hello:hello"
label = "Short"
```

---

## 2. Entry lifecycle globals

The script's top level runs once at load — set up state and register `noctalia.state.watch` handlers there.

| Function | Widget | Shortcut | Launcher | Desktop | Panel | Service | When |
|---|---|---|---|---|---|---|---|
| `update()` | ✓ | ✓ | ✓ | ✓ | | | every update interval |
| `onClick()` / `onRightClick()` | ✓ | ✓ | | | | | pointer press |
| `onMiddleClick()` | ✓ | | | | | | middle press |
| `onScroll(axis, steps, startsGesture)` | ✓ | | | | | | wheel/touchpad scroll |
| `onQuery(text)` | | | ✓ | | | | launcher text changed (behind prefix) |
| `onActivate(id)` | | | ✓ | | | | launcher result selected |
| `onEnable()` | | | | | | ✓ | plugin explicitly enabled (API 17) |
| `onOpen(context)` / `onClose()` | | | | | ✓ | | panel opened / closed |
| `onKey(chord, pressed)` | | | | | ✓ | | captured chord while panel focused (API 13) |
| `onFrameTick(deltaMs)` | | | | ✓ | ✓ | | every frame after `setNeedsFrameTick(true)` (API 18) |
| `onIpc(event, payload)` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | `noctalia msg plugin …` |
| `onConfigChanged()` | | | | | | ✓ | a plugin setting changed |
| `onExit(signal, reason)` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | runtime about to be destroyed (reason needs API 17) |
| `onOutputsChanged()` | | | | | | ✓ | output set/geometry changed |

### `onExit(signal, reason)`

Runs on normal Noctalia exit, disable/remove, or reload. `signal`: `2` SIGINT, `15` SIGTERM, `0` other teardown. `reason` (API 17): `"disable"`, `"uninstall"`, `"reload"`, `"shutdown"`. Handlers accepting only `signal` stay compatible (Luau ignores the extra arg). Keep cleanup short (normal callback budget); cannot run after SIGKILL/crash. Detach long cleanup with `noctalia.runAsync(cmd)` (no callback) — it outlives the runtime, but must avoid plugin-directory files (removed on uninstall) and be idempotent.

### Lifecycle changes in a service (API 17)

- `onEnable()` runs after an explicit enable succeeds and on re-enable of a disabled plugin — **not** on normal startup, source update, script reload, or settings-driven restart. Use top-level init for normal startup.
- `onConfigChanged()`: host updates settings in place, keeps timers/caches/connections, `noctalia.getConfig()` returns new values. Without it, the host restarts the service runtime (top-level re-runs with new settings). `noctalia.state` is process-lifetime and survives a restart — key any cache stored there by the config it depends on.

### Modules (`plugin_api = 22`)

```lua
local format = require("./lib/format.luau")
```

- Argument must start with `./` or `../` and end in `.luau`; anything else fails. Paths are lexical (resolve relative to the file containing the call). `../` can leave the plugin dir (trusted API).
- A module must return exactly one non-`nil` value; runs in the entry's VM with its own global environment (`noctalia.*`, `ui.*` visible; `_G` is the module env).
- Per-entry module cache: same canonical path = cached; a different entry gets a separate instance; circular imports fail with the full chain.
- Editing a successfully loaded module hot-reloads the owning entry (including one first required inside a callback). A module that failed to load is not cached/watched — touch the entry or another loaded file to retry.

### `onScroll(axis, steps, startsGesture)`

- `axis`: `"vertical"`/`"horizontal"`; `steps`: whole wheel detents (negative = up/left, positive = down/right); mouse wheel = 1 step/notch, touchpad accumulates.
- `startsGesture` = true only on the first step of a gesture in a given direction. Ramp a value taking every step; step a list on `startsGesture` and let the burst fall through.
- Undefined `onScroll` → events pass to the bar underneath. Host `enable_scroll` (default `true`) gates wheel/touchpad delivery to `onScroll`; `false` silences the callback. A bound `scroll_up` runs its action instead of `onScroll`.

---

## 3. `barWidget.*` — widget presentation

`setText` · `setGlyph` · `setImage` · `setTooltip` · `clearTooltip` · `setFont` · `setColor` · `setGlyphColor` · `setVisible` · `isVertical` · `outputName` · `render(tree)`

- Imperative setters patch the built-in glyph/text row; `barWidget.render(tree)` replaces it with a `ui.*` tree (composite content). Once `render()` is called, later `setText`/`setGlyph` have no visible effect and log a warning.
- `outputName()` → connector name of the bar this instance is on (`nil` unknown); per-placement, unlike `noctalia.focusedOutputName()`.
- Custom fonts: `noctalia.loadFont(path)` → family name; pass to `setFont(family, baseline?)`. Baselines: `"text"` (default, cap-band centered), `"textFixedHeight"` (locked row height), `"inkCentered"` (centers glyph ink), `"pictographic"` (art/icon fonts anchored at ink top).

---

## 4. `shortcut.*` — control-center tile

`setLabel(text)` · `setIcon(on [, off])` · `setActive(bool)` · `setEnabled(bool)`

```lua
local on = noctalia.state.get("toggled") == true
local function render()
  shortcut.setLabel(on and "On" or "Off")
  shortcut.setIcon("bulb")
  shortcut.setActive(on)
end
render()
function onClick()
  on = not on
  noctalia.state.set("toggled", on)
  render()
end
```

---

## 5. `launcher.*` — launcher provider

Manifest fields: `prefix` (trigger word — bare word, host prepends `/`; do not include the prefix character), `glyph` (default result icon), `include_in_global_search` (default `false`), `debounce_ms` (wait after last keystroke before `onQuery`; set for network providers; default `0`).

- `setResults(query, results)` — `query` **must echo** the `text` from `onQuery` (late results map back; latest wins). Empty list clears.
- Result shape: `{ id, title, subtitle?, glyph?, icon?, badge?, query?, score? }`. `id` → `onActivate` unless `query` set. Ordered by `score` desc, then insertion. `badge` draws in place of `glyph`/`icon`.
- `setQuery(query)` — replaces the open launcher's raw input and **stays open**, re-running `onQuery`. Use from `onActivate` (or a result-level `query`) for drill-in: e.g. `"/tr french "` to stay routed. An `onActivate` that does not call `setQuery` closes the launcher.
- `noctalia.fuzzyScore(pattern, text)` — native fuzzy matcher, returns score or `nil`.
- Queries run off the UI thread — publish a placeholder synchronously, then `setResults` again from the async callback.

---

## 6. Declarative UI

`desktopWidget.render(tree)` / `barWidget.render(tree)` / `panel.render(tree)` take a retained `ui.*` tree; Noctalia diffs each render against the previous and updates native controls in place.

### `ui.*` control vocabulary

Sizes are logical px scaled with the surface. Every control also accepts `width`, `height`, `flexGrow`, `opacity`, `visible`. Unknown control type or prop is logged and skipped.

| Constructor | Props |
|---|---|
| `ui.column` / `ui.row` | `gap`, `padding`, `paddingH`, `paddingV`, `align` (`start`/`center`/`end`/`stretch`), `justify` (`start`/`center`/`end`/`space_between`), `fill`, `radius`, `border`, `borderWidth`, `minWidth`, `minHeight`, `onClick`, `onHover` |
| `ui.scroll` | column layout props + `fill`, `radius`, `border`, `borderWidth`, `stickToBottom` (bool, API 21), `onScroll` (`(offset, maxOffset)` strings, API 21), `scrollToBottomRev` (number, API 21) |
| `ui.label` | `text`, `fontSize`, `color`, `fontWeight` (`thin`…`heavy`), `fontFamily`, `baseline` (`text`/`textFixedHeight`/`inkCentered`/`pictographic`), `maxWidth`, `maxLines`, `textAlign` |
| `ui.markdown` | `text` (markdown source; API 21), `width`, `height` |
| `ui.glyph` | `name` (Tabler/Nerd-Font), `size`, `color` |
| `ui.image` | `path` (plugin-relative, `~`, or absolute; local files only), `width`, `height`, `radius`, `fit` (`contain`/`cover`/`stretch`), `border`, `borderWidth`, `onClick`, `onHover` |
| `ui.box` | `fill`, `radius`, `border`, `borderWidth`, `softness`, `width`, `height`, `onClick`, `onHover` |
| `ui.separator` | `thickness`, `color`, `spacing`, `orientation` (`auto`/`horizontal`/`vertical`) |
| `ui.spacer` | flexible filler (use `flexGrow`) |
| `ui.progress` | `progress` (0–1), `fill`, `track`, `radius`, `width`, `height` |
| `ui.button` | `text`, `glyph`, `fontSize`, `glyphSize`, `variant` (`default`/`primary`/`secondary`/`destructive`/`outline`/`ghost`), `contentAlign`, `controlSize` (`sm`/`md`/`lg`), `tooltip`, `enabled`, `selected`, `onClick`, `onRightClick`, `onHover` |
| `ui.graph` | `values`/`values2` (0–1 arrays), `color`/`color2`, `lineWidth`, `fillOpacity`, `width`, `height` |
| `ui.toggle` | `checked` (bool), `enabled`, `onChange` |
| `ui.slider` | `min`, `max`, `step`, `value`, `controlSize`, `enabled`, `onChange`, `onDragEnd` |
| `ui.select` | `options` (string array), `selectedIndex`, `placeholder`, `controlSize`, `enabled`, `width`, `height`, `onChange` |
| `ui.input` | `value` (initial text only), `placeholder`, `fontSize`, `controlSize`, `password` (bool), `multiline` (bool), `submitOnEnter` (bool, API 21), `focus` (bool), `enabled`, `onChange`, `onSubmit` |

### Color props

Palette role token (`primary`, `on_surface`, …), token with alpha suffix (`primary/0.6`, resolved live against the palette), or hex (`#rrggbb` / `#rrggbbaa`).

### Behavior rules

- **`opacity` is group opacity** (fades children too). For a translucent background only, use a translucent `fill`: `ui.column({ fill = "surface_variant/0.6" }, …)`.
- **Layout default**: column/row/scroll **stretch** children across the cross axis (like CSS flexbox). Override per node with `align`.
- **`controlSize`**: `sm` 32px, `md` 38px (default), `lg` 44px, scaled with surface. `height` wins when both set. (`ui.glyph`'s numeric `size` is px, unrelated.)
- **Tooltips**: `ui.button` `tooltip` string, shown on hover (bar widgets and panels; not desktop widgets). Dropping the prop clears it.
- **Callbacks**: a function (API 9) or the name of a global function. `onClick` on click; `onChange` passes value as a string (`"true"`/`"false"` toggle, number slider, text input, index select); `onSubmit` on Enter. Closures capture scope — perfect for per-row handlers; give repeated nodes a `key` so handlers survive re-render.
- **Hover**: `onHover` on row/column/box/image/button → handler receives state (`"true"`/`"false"`) and node `key`. Only the innermost hovered element reports. Every `"true"` is matched by a `"false"` (even if the node disappears), so hover flags never stick.
- **Clickable containers**: `onClick` on row/column/image/box makes the whole container a click target (joins keyboard tab order, Enter/Space activates). `onHover`-only containers do not swallow clicks. Empty `onClick`/`onHover` name counts as unset.
- **Multiline input** (`multiline = true`, API 21): Enter inserts newline, `onSubmit` fires on Ctrl+Enter; `submitOnEnter = true` flips it for chat composers (Enter submits, Shift+Enter newline, Ctrl+Enter still submits). `multiline` and `password` are mutually exclusive.
- **Markdown** (API 21): read-only block; re-parses only when `text` or surface scale changes.
- **Follow-scroll** (API 21): `stickToBottom = true` pins while content grows until the user scrolls away; `scrollToBottomRev` jumps on first render that sees it and again when the number changes.
- **Focus**: `ui.input` `focus = true` grabs focus once at creation only — give the input a fresh `key` to re-focus.
- **Controlled vs uncontrolled**: toggle/slider/select are value-driven (repass every render); `ui.input` is uncontrolled (`value` seeds once, host owns the text; read via `onChange`/`onSubmit`; stable `key` keeps text across renders).
- **Identity**: give list children a `key` so reordering reuses native controls.
- **Images**: local files only — download remote previews with `noctalia.download(url, dest, cb)` first.
- **Glyph-only buttons**: setting only `glyph` clears any previous `text`.
- **Ticks**: `setWantsSecondTicks(true)` runs `update()` on second boundaries; `setNeedsFrameTick(true)` delivers `onFrameTick(deltaMs)` every frame (coalesced — slow scripts only see the latest). No frame-tick API in the bar.
- **Position is host-owned** for desktop widgets (user places/sizes/rotates in the editor).

### `desktopWidget.*`

`render(tree)` · `setWantsSecondTicks(bool)` · `setNeedsFrameTick(bool)`

```lua
local color = noctalia.getConfig("color")
function update()
  desktopWidget.setWantsSecondTicks(true)
  desktopWidget.render(ui.column({ gap = 10, align = "center" }, {
    ui.label({ text = os.date("%H:%M:%S"), fontSize = 32, fontWeight = "bold", color = color }),
    ui.row({ gap = 8 }, {
      ui.button({ text = "Ping", variant = "primary", onClick = "ping" }),
    }),
  }))
end
function ping()
  noctalia.notify("Desktop widget", "button clicked")
end
```

Reference: `noctalia/timer`.

### `barWidget.render` — bar widget `ui.*`

- Cross-axis is the bar thickness: keep the tree one control tall (row on horizontal, column on side — branch on `barWidget.isVertical()`); only the main axis grows.
- No keyboard: `ui.input`, `ui.select`, `ui.scroll` skipped with a warning. Pointer controls work.
- Inline controls consume their own clicks; widget-level `onClick`/`onRightClick` still fire on the rest of the capsule (and padding).
- Ticks stay on `noctalia.setUpdateInterval` — no frame-tick in the bar.

Reference: `declarative` widget of `noctalia/example`.

### `panel.*` — declarative panel

`render(tree)` · `close()` · `setWantsSecondTicks(bool)` · `setNeedsFrameTick(bool)` (API 18)

- **Size is host-owned**: `width`/`height` on the `[[panel]]` entry — positive px or `"fill"` (spans output's available extent minus exclusive zones; `"fill"` requires `placement = "floating"`). No `setSize` at runtime. Oversized fixed px clamp to the output.
- `dismiss_on_outside_click = false` for auth prompts (default `true`; API 8). Escape and an explicit Close/Cancel still dismiss.
- `setNeedsFrameTick(true)` delivers `onFrameTick(deltaMs)` while open (API 18); ticks stop on close, resume on open.
- Render in `onOpen(context)` and from any state-changing callback (`context` is the optional string from `panel-open <id> [context]`).

#### Panel options (manifest keys)

| Key | Notes |
|---|---|
| `placement` | `attached` (anchors to bar edge) or `floating` (default). Host injects a `<entry>_placement` plugin setting. |
| `position` | `auto`, `center`, or screen anchor; floating only; `<entry>_position` setting. |
| `open_near_click` | open near the toggling bar widget (default `false`); `<entry>_open_near_click`. |
| `dismiss_on_outside_click` | manifest only; default `true` (API 8). |
| `keyboard_focus` | `on_demand` (default), `exclusive`, or `none` (API 10). `none` requires `dismiss_on_outside_click = false`. |
| `persistent` | stays open when another panel opens (API 11); requires `dismiss_on_outside_click = false`; forces floating; rejects `keyboard_focus = "exclusive"`; no `ui.select` dropdowns/menus. |
| `capture_keys` | chords the panel handles itself while focused (API 13); see below. |

Users override through plugin-settings GUI or `[plugin_settings."author/plugin"]` (e.g. `browser_placement = "floating"`). Official defaults: `noctalia/example:panel` = `floating` + `center`; `noctalia/wallhaven:browser` = `attached` + `auto`.

#### Handling keys directly (`capture_keys` / `onKey`, API 13)

```toml
[[panel]]
id           = "timer"
entry        = "panel.luau"
capture_keys = ["space", "ctrl+r"]
```

```lua
function onKey(chord, pressed)
  if chord == "space" then
    if pressed then arm() else start() end
  elseif chord == "ctrl+r" and pressed then
    reset()
  end
end
```

- Only declared chords are received; `pressed` distinguishes press/release; match the exact chord string from the manifest. Chord syntax: `space`, `ctrl+r`, `shift+Return`.
- A focused `ui.input` wins over `onKey` for printable keys. Escape always dismisses (cannot be captured). Captured chords outrank shell nav keybinds inside that panel only. Key repeat is filtered (one press + one release). Super chords rejected. `keyboard_focus` must not be `none`.

Toggle from a script: `noctalia.togglePanel("author/plugin:panel")`. Externally: `noctalia msg panel-toggle noctalia/example:panel`.

Reference: `panel` entry of `noctalia/example`; `noctalia/wallhaven:browser` (network-backed).

### Drag and drop (panels only, API 5)

The host owns the interaction (pointer capture, hit testing, ghost, highlighting, cursor); the plugin gets **one callback after a completed drop**, mutates its model, and re-renders.

| Constructor | Props |
|---|---|
| `ui.dragSource` | `dragType` (**required**), `payload` (**required**, first callback arg), `enabled`, `tooltip`, `previewAncestor` (int 0–8: parent levels the ghost shows), `liftFromLayout` (bool) |
| `ui.dropZone` | `accepts` (**required** array; `{}` accepts nothing), `value` (**required**, second callback arg), `onDrop` (**required**), `direction` (`column`/`row`), `enabled`, `expandOnDrag` (bool), `hitSlop` (number) |

- A press becomes a drag only after a movement threshold; clicks inside dragged rows still work. Releasing over an accepted zone calls `onDrop(payload, value)`; elsewhere cancels silently. Nested zones resolve deepest; `hitSlop` zones considered first, closest wins.
- **Sortable lists**: thin `expandOnDrag` + `hitSlop` insertion zone before every row and one after the last; with `liftFromLayout` the list shows exactly one open gap following the pointer. Encode the insertion point in `value` (`"before:<id>"`, `"end"`, …) — the callback never receives coordinates.
- **Validation strict**: missing/mistyped/empty/over-limit required props log and disable that control for the render. Limits: `payload` 16 KiB; `dragType`/`value`/`onDrop`/`accepts` entries 256 bytes; ≤16 `accepts` entries.
- Mutate + `render()` first, then persist; keep a snapshot to roll back; `enabled = false` while a save is in flight.
- Panels only; drags stay inside one panel; left button only; no OS/Wayland DnD, no keyboard drag (keep a non-drag alternative), no wheel-scroll while dragging.

---

## 7. Runtime API (`noctalia.*`)

Most are synchronous. Methods starting subprocesses, HTTP, or downloads return a boolean immediately (accepted?) then deliver results to a callback.

### Runtime & settings

| Method | Returns | Notes |
|---|---|---|
| `setUpdateInterval(ms)` | — | how often `update()` runs; <16ms clamped |
| `log(msg)` | — | log with the plugin's script context |
| `isDarkMode()` | bool | active theme mode is dark |
| `focusedOutputName()` | string\|nil | focused output connector |
| `getConfig(key)` | value\|nil | declared plugin/entry setting; undeclared → warning + nil |

### Outputs, wallpaper, panels

| Method | Returns | Notes |
|---|---|---|
| `outputs()` | array | `{ name, description, width, height, x, y, scale, focused }`; `name` is DRM connector |
| `setWallpaperEnabled(connector, enabled)` | — | runtime-only, clears on restart |
| `setWallpaper(path)` / `setWallpaper(connector, path)` | — | applies + persists wallpaper |
| `wallpaperDirectory()` | string\|nil | resolved wallpaper folder for current theme mode |
| `togglePanel("author/plugin:panel")` | — | open/close by full entry id |
| `openSettings()` | — | opens settings at this plugin's own page (API 15); warns when plugin declares none |

Prefer the API paths over shelling out to the `noctalia` CLI (in-process, no IPC round trip). `[[service]]` may define `onOutputsChanged()`.

### Dialogs

| Method | Returns | Notes |
|---|---|---|
| `openColorPicker(initialColor, onClose)` | bool | `#RRGGBB` initial; callback gets canonical `#RRGGBB` or `nil`; one pending picker per entry |

### Application icons

| Method | Returns | Notes |
|---|---|---|
| `appIconPath(appId, sizePx?)` | string\|nil | taskbar-equivalent lookup; raw icon names (e.g. `"folder-music"`) resolve too; path plugs into `ui.image`; cache results keyed by app id |

### Time, notifications, clipboard

| Method | Returns | Notes |
|---|---|---|
| `formatTime(pattern)` / `(pattern, unixSeconds)` / `(pattern, unixSeconds, timezone)` | string | `%s` expands to epoch seconds; timezone needs API 19 |
| `timeFormat()` / `dateFormat()` | string | mirrors `[shell]` formats (API 19) |
| `isValidTimezone(name)` | bool | empty = system local (API 19) |
| `nowMs()` | number | sub-second wall clock (API 12) |
| `notify(title, body?)` / `notifyError(title, body?)` | — | notifications |
| `copyToClipboard(text, mime)` | bool | e.g. `"text/plain"`, `"text/uri-list"` |
| `clipboardText()` | string\|nil | latest text clipboard |

### System stats (API 12; API 16 additions)

| Method | Returns | Notes |
|---|---|---|
| `systemStats()` | table\|nil | host monitor snapshot; first call opts into CPU temp + GPU probes (released on unload); `nil` when `[system.monitor]` disabled |
| `cpuCores()` | array\|nil | per-core %, `/proc/stat` order; needs two reads (~1s) for first result; not enabled by `systemStats()` |
| `diskMounts()` | array | `{ path, source, filesystem }`, deduped by source, sorted by path (API 16) |
| `diskStats(path)` | table\|nil | `{ usagePercent, totalBytes, freeBytes, availableBytes }` (API 16) |

`systemStats()` fields: `sampledAtMs`, `cpu.{usagePercent, tempC?, freqMhz?, maxFreqMhz?}`, `ram.{usagePercent, usedMb, totalMb}`, `swap.{usedMb, totalMb}`, `gpu.{tempC?, usagePercent?, vramUsedBytes?, vramTotalBytes?}`, `net.{rxBytesPerSec, txBytesPerSec, interfaces}` (interfaces API 16), `loadAvg`. Absent sensors are `nil` (test with `~= nil`), not `0`. Values refresh on `[system.monitor]` poll intervals (CPU every 2s default), not per call.

### Subprocesses & environment

| Method | Returns | Notes |
|---|---|---|
| `runAsync(cmd)` | bool | detached shell command, no output |
| `runAsync(cmd, cb)` | bool | `cb({ exitCode, stdout, stderr, timedOut, stdoutTruncated, stderrTruncated })` |
| `runStream(cmd, onLine)` | bool | long-lived; `onLine(line)` per stdout line; terminated on reload/remove/stop |
| `runInTerminal(cmd)` | bool | uses `$TERMINAL` (no `-e` in value), else discovers on `PATH` |
| `commandExists(name)` | bool | executable on `PATH` |
| `processMatches(cb, ...needles)` | bool | async; `cb(matched)` bool |
| `flatpakAppInstalled(id)` | bool | |
| `portalAvailable()` | bool | desktop portal available |
| `getenv(name)` | string\|nil | |
| `expandPath(path)` | string | e.g. `~/Pictures` → absolute |

### Filesystem

Paths resolve: `~` → `$HOME`, absolute as-is, relative against the plugin's own directory. Trusted, not sandboxed.

| Method | Returns | Notes |
|---|---|---|
| `readFile(path)` | string \| `nil, err` | bytes |
| `readFileAsync(path, cb)` | bool | bounded (4 MiB, ≤4 outstanding per runtime); `cb(contents, nil)` / `cb(nil, err)` (API 23) |
| `writeFile(path, content)` | bool, err? | replaces |
| `mkdirAll(path)` | bool, err? | creates parents; existing dir = success |
| `removeFile(path)` | bool, err? | refuses directories |
| `renameFile(from, to)` | bool, err? | |
| `fileExists(path)` | bool | |
| `fileInfo(path)` | table \| `nil, err` | `{ size, mtime, isDir }` |
| `listDir(path)` | array \| `nil, err` | filenames |
| `pluginDir()` | string\|nil | runtime dir — do NOT persist here (rewritten on update) |
| `pluginDataDir()` | string \| `nil, err` | persistent per-plugin dir, created on demand, survives updates |
| `loadFont(path)` | string \| `nil, err` | returns family name |

**Persistence pattern:**
```lua
local dir = noctalia.pluginDataDir()
local path = dir .. "/data.json"
noctalia.writeFile(path, noctalia.json.encode(myTable))          -- save
local raw = noctalia.readFile(path)
if raw then myTable = noctalia.json.decode(raw) end               -- restore
```

### Sound (API 20)

| Method | Returns | Notes |
|---|---|---|
| `sound.load(name, path, onLoaded)` | bool | async decode; `onLoaded(ok, err)`; ≤8 pending; relative paths resolve like filesystem |
| `sound.play(name)` | — | plays from this runtime's bank; suppressed if already playing |

Define the callback before loading; play only after success. Names scoped to the runtime; reload/stop cancels pending loads. Honors `[audio].enable_sounds` and `sound_volume`.

### HTTP & downloads

`request` table: `{ url, method, body, headers = { "Accept: application/json" }, basic_username, basic_password, follow_redirects = false, allow_insecure_tls = false (API 7) }`. Only `url` required. `allow_insecure_tls` disables cert-chain + hostname verification (keep false unless explicitly trusted; applies to `http()` and `httpStream()`).

| Method | Returns | Notes |
|---|---|---|
| `http(request, cb)` | bool | `cb({ ok, status, body })` |
| `httpStream(request, onLine, onClose)` | handle\|nil | long-lived (SSE); `onLine(line)` per line (CR trimmed); `onClose(result)` exactly once (`{ ok, status }`; non-2xx body streams to onLine); handle has `stop()` (idempotent, suppresses onClose); no transfer timeout — caller reconnects; cancelled on reload/remove/stop |
| `download(url, dest, cb)` | bool | `cb(ok)`; `dest` resolves like filesystem (relative → plugin dir) |

Credentials in an `Authorization` header never appear on a process command line (unlike a spawned `curl`).

### Translations & data helpers

| Method | Returns | Notes |
|---|---|---|
| `tr(key)` | string | from `translations/<lang>.json`, falls back to key |
| `tr(key, subst)` | string | replaces `{name}` placeholders |
| `trp(key, count)` / `trp(key, count, subst)` | string | plural; prefers `<key>.one`/`<key>.other`, then bare key; `{count}` available |
| `json.decode(str)` | value \| `nil, err` | |
| `json.encode(value)` / `json.encode(value, true)` | string \| `nil, err` | second arg = pretty |
| `string.trim(str)` | string | |
| `string.urlEncode(str)` | string | percent-encode (prefer over manual building) |
| `string.urlDecode(str)` | string | |
| `fuzzyScore(pattern, text)` | number\|nil | nil = no match |

### Sharing state across entries

Entries are isolated VMs — they exchange **plain values** through a per-plugin channel:

| Method | Returns | Notes |
|---|---|---|
| `state.set(key, value)` | — | publish a plain value |
| `state.get(key)` | value\|nil | latest value |
| `state.watch(key, fn)` | — | `fn(value)` on change |

Values are copied — plain data only (no functions). Typical: a `[[service]]` publishes, widget/shortcut watch. **In-memory only** — not saved to disk; cleared when the plugin stops. For durable data use `pluginDataDir()`.

---

## 8. Plugin API versions

Every plugin declares the oldest level required in `plugin.toml`. Cumulative: use the oldest that covers every capability used. Noctalia currently supports **3–23**; outside that range the plugin cannot run.

| API | Noctalia | Introduced |
|---|---|---|
| `3` | v5.0.0-beta.3 | Mandatory `plugin_api` (replaces `min_noctalia`) |
| `4` | v5.0.0-beta.4 | `noctalia.httpStream()` |
| `5` | v5.0.0-beta.4 | `ui.dragSource()` / `ui.dropZone()` |
| `6` | v5.0.0-beta.4 | `string_map` setting type |
| `7` | v5.0.0-beta.4 | `allow_insecure_tls` HTTP option |
| `8` | v5.0.0-beta.4 | `dismiss_on_outside_click` panel option |
| `9` | v5.0.0-beta.5 | Luau closures in UI callback props |
| `10` | v5.0.0-beta.5 | `keyboard_focus` panel option |
| `11` | v5.0.0-beta.5 | `persistent` panel option |
| `12` | v5.0.0-beta.5 | `systemStats()`, `cpuCores()`, `nowMs()` |
| `13` | v5.0.0-beta.5 | `capture_keys` + `onKey` |
| `14` | v5.0.0-beta.5 | `[widget.actions]` gesture defaults |
| `15` | v5.0.0-beta.6 | `openSettings()` |
| `16` | v5.0.0-beta.6 | per-interface net rates, sample timestamps, disk APIs |
| `17` | v5.0.0-beta.7 | services start on enable; `onExit` reason; `onEnable()` |
| `18` | v5.0.0-beta.7 | `panel.setNeedsFrameTick(bool)` |
| `19` | v5.0.0-beta.7 | timezone `formatTime`, `isValidTimezone`, `timeFormat()`/`dateFormat()` |
| `20` | v5.0.0-beta.7 | `noctalia.sound.load()` / `sound.play()` |
| `21` | Unreleased | `ui.markdown`, `submitOnEnter`, `stickToBottom`/`onScroll`/`scrollToBottomRev` |
| `22` | Unreleased | `require("./path.luau")` modules with hot reload |
| `23` | Unreleased | `noctalia.readFileAsync()` |

Raising `plugin_api` drops the plugin from every Noctalia below it. Keep older users covered with `[[plugin.release]]` catalog rows (see below).

---

## 9. Workflow & publishing

### Local development

1. Drop the plugin under `$XDG_DATA_HOME/noctalia/plugins/<plugin>/` (outranks all sources) **or** add a `path` source: `noctalia msg plugins source add my-dev path ~/dev/my-plugins`.
2. Enable once. `.luau` edits hot-reload automatically; manifest changes apply on next config reload.
3. IPC-test an entry's `onIpc` handler:
   ```
   noctalia msg plugin me/hello:hello focused greet "hi there"
   noctalia msg plugin me/hello:ticker all refresh
   noctalia msg panel-toggle me/hello:panel
   ```
   Targets: `focused` | connector (`DP-1`) | `<connector>:<bar-name>` | `all` (required for singletons — service, panel).

**Source precedence**: the local data dir overrides everything; later-added sources override earlier; user sources override built-in `official`/`community`. So clone the official/community repo, add it as a source, and edit in place to override built-ins — no id renames needed.

### Publishing (source repos)

One repo holds many plugins, each in its own subdirectory matching the id part after `/` (`me/hello` lives at `hello/`). A root `catalog.toml` indexes every plugin (compat-checked without a full clone):

```toml
[[plugin]]
id           = "me/hello"
name         = "Hello"
version      = "1.0.0"
author       = "me"
license      = "MIT"
icon         = "puzzle"
description  = "A friendly greeter."
deprecated   = false
plugin_api   = 3
tags         = ["demo"]
dependencies = ["slurp"]
```

Catalog rows require `id`, `name`, and a positive integer `plugin_api`; rows without them are ignored.

### Keeping older Noctalia versions supported

Add a `[[plugin.release]]` row per API level your history supports, newest first:

```toml
[[plugin]]
id         = "me/hello"
version    = "2.0.0"
plugin_api = 9

[[plugin.release]]
plugin_api = 3
version    = "1.4.0"
rev        = "5082ed5f85e795513b8485e4cedc66d5a2c816ff"
```

Each row needs `plugin_api`, `version`, and a full 40-char `rev`; malformed rows or rows at/above the tip's level are dropped. The host picks the newest release its API range allows and exports that exact commit. Generate with `update-catalog.py` in the official/community repos (needs full history, `fetch-depth: 0`). Release rows apply to `git` sources only.

Users add the repo with `noctalia msg plugins source add <name> git <url>`, then enable plugins from it.

### Sharing to the store

Open a PR against `github:noctalia-dev/community-plugins` (README has submission rules). A plugin ships: `plugin.toml`, entry scripts, `README.md`, `thumbnail.webp`, `translations/en.json`. CI validates all of it and regenerates the catalog on merge. Directory names are first-come (a plugin named `weather` exists only once). `official-plugins` is core-team only and does not take third-party plugins.

---

## Reference implementations

- `noctalia/example` — widget + service + shortcut sharing state; `panel` (settings-style, every interactive control); `declarative` widget.
- `noctalia/timer` — desktop widget (countdown, progress bar).
- `noctalia/screen_recorder` — full real-world plugin.
- `noctalia/wallhaven` — network-backed panel (thumbnail grid, filters, download + apply).
