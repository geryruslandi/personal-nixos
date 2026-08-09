---
name: noctalia-plugin
description: Use when creating, writing, or modifying Noctalia v5 plugin code — plugin.toml manifests, Luau entry scripts (widgets, shortcuts, launcher providers, desktop widgets, panels, services), ui.* declarative trees, the noctalia.* runtime API, plugin API levels, and plugin workflow/publishing. Trigger phrases: "create a noctalia plugin", "write a noctalia plugin", "add a plugin entry", "plugin.toml", "noctalia bar widget script". Do NOT use for editing the shell config (home-modules/noctalia.nix) — use the 'noctalia' skill — and do NOT use for syncing GUI settings changes into the repo — use the 'noctalia-sync' skill.
---

# Noctalia v5 Plugin Development

Plugins are **trusted code**: a directory with a static `plugin.toml` manifest plus one or more Luau (`.luau`) entry scripts, each running in its own isolated VM off the UI thread with per-call time budgets. Installing one is equivalent to running a user-owned script. The API is **beta** — manifest format and APIs may change before v5 is stable.

## Plugin anatomy

```
my-plugin/
  plugin.toml          # manifest: identity + entries + settings schema
  widget.luau          # an entry script
  translations/en.json # REQUIRED if the manifest declares any settings (label_key)
  data.txt             # any files scripts read at runtime (relative paths resolve to plugin dir)
```

- **Entry kinds**: `[[widget]]` (bar widget), `[[shortcut]]` (control-center tile), `[[launcher_provider]]` (launcher prefix results), `[[desktop_widget]]` (tile, `ui.*` tree), `[[panel]]` (pop-up surface, `ui.*` tree), `[[service]]` (headless loop feeding the others).
- **Addressing**: an entry is `<author>/<plugin>:<entry-id>` — a bar widget is configured as `type = "me/hello:hello"`; plugin settings id is `<author>/<plugin>`.

## Minimal widget (bar)

`plugin.toml`:
```toml
id         = "me/hello"
name       = "Hello"
version    = "1.0.0"
plugin_api = 3
author     = "me"

[[widget]]
id    = "hello"
entry = "widget.luau"
```

`widget.luau`:
```lua
function update()
  noctalia.setUpdateInterval(1000)
  barWidget.setGlyph("puzzle")
  barWidget.setText("Hello")
end

function onClick()
  noctalia.notify("Hello", "you clicked me")
end
```

## Composite template (service feeds a widget)

`[[service]]` publishes values over `noctalia.state`; the widget watches them. State is **in-memory only** (cleared when the plugin stops) and copies plain values across VMs — never functions.

```lua
-- ticker.luau (service)
noctalia.setUpdateInterval(1000)
local n = 0
function update()
  n = n + 1
  noctalia.state.set("count", n)
end
```
```lua
-- widget.luau
noctalia.state.watch("count", function(value)
  barWidget.setText(tostring(value))
end)
```

## Scaffolding & local development

1. Drop the plugin under `$XDG_DATA_HOME/noctalia/plugins/<author>/<plugin>/` (this outranks every source — fastest loop), **or** add a source pointing at your dev dir: `noctalia msg plugins source add my-dev path ~/dev/my-plugins` (plugins live in `my-plugins/<plugin>/`).
2. Enable once: `noctalia msg plugins enable <author>/<plugin>`.
3. Edits to `.luau` files **hot-reload automatically**; manifest changes are picked up on the next config reload.
4. Drive `onIpc(event, payload)` from the shell to test:
   ```
   noctalia msg plugin me/hello:hello focused greet "hi there"
   noctalia msg plugin me/hello:ticker all refresh
   noctalia msg panel-toggle me/hello:panel
   ```
   Targets: `focused`, a connector (`DP-1`), `focused:top`, or `all` (required for singletons — `[[service]]`, `[[panel]]`).
5. Logging/errors: `noctalia.log(msg)` writes with the script's context; unknown control/prop names and undeclared config keys surface as loud warnings in the log, not silent failures.

## Entry-kind decision guide

| Need | Entry kind |
|------|-----------|
| Compact info/action strip on a bar | `[[widget]]` |
| Toggle tile in control center | `[[shortcut]]` |
| Type-ahead results behind a `/prefix` in the launcher | `[[launcher_provider]]` |
| Always-placed tile on the desktop | `[[desktop_widget]]` |
| Pop-up surface (search, settings, forms, drag-drop lists) opened by id | `[[panel]]` |
| Background loop other entries read (network fetch, polling) | `[[service]]` |

## Key conventions & pitfalls

- **`plugin_api` is mandatory and cumulative.** Use the oldest level that covers every capability used; Noctalia currently supports 3–23. Check the capability table in `reference/plugin-development.md` before using a newer API. Raising it drops the plugin from older Noctalia versions.
- **Settings are translation-keyed.** A setting uses `label_key`/`description_key` (literal `label`/`description` fields are rejected) and the text lives in `translations/<lang>.json` — a plugin with settings needs `translations/en.json`. `label_key` is required; `key` is required; only declared keys resolve via `noctalia.getConfig()` (undeclared → warning + `nil`, no silent fallback).
- **Widget vs plugin settings**: a `[[setting]]` at the manifest root is shared by every entry and edited under Settings → Plugins (the gear on the plugin row). A `[[widget.setting]]` is per-widget-instance, edited with the bar widget's own settings. When both declare the same key, the widget entry value wins for that widget.
- **Persistence**: `noctalia.state` is memory-only. For data surviving restarts write to `noctalia.pluginDataDir()` (per-plugin folder, survives updates) — never `noctalia.pluginDir()`, which is a runtime copy rewritten on update.
- **Middle click**: every widget gets a built-in `middle` binding that opens its settings, so `onMiddleClick` does not fire out of the box. Declare `middle = "none"` in `[widget.actions]` to free the button.
- **Bindings beat callbacks**: a user binding in `[widget.<name>.actions]` overrides your `onClick`/`onRightClick`/`onScroll`. You can declare defaults in `[widget.actions]` (API 14); gestures neither bound nor declared still reach your callbacks.
- **Scroll**: `onScroll(axis, steps, startsGesture)` — `startsGesture` is true only on the first step of a gesture. List-stepping should act on `startsGesture`; value-ramping should take every step. `enable_scroll = false` silences the callback outright.
- **`ui.input` is uncontrolled**: `value` seeds the field once, the host owns the text afterwards. Toggles/sliders/selects are value-driven (repass the value every render). Give repeated/reordered list nodes a `key` so handlers and native controls survive re-renders.
- **Bar `ui.*` constraints**: cross-axis is the bar thickness (keep the tree one control tall — branch on `barWidget.isVertical()`); no keyboard, so `ui.input`/`ui.select`/`ui.scroll` are skipped with a warning; inline controls consume their own clicks while widget-level `onClick` still fires on the rest of the capsule.
- **Panel size is host-owned**: declare `width`/`height` on the `[[panel]]` entry (positive px or `"fill"`); there is no `setSize` at runtime.
- **onConfigChanged vs restart**: services get `onConfigChanged()` (settings updated in place, state preserved); without it the service runtime is restarted. `noctalia.state` survives a restart, so cache data there keyed by the config it depends on.

## Enabling a plugin in this NixOS repo

The shell ships built-in plugins from the `official`/`community` git sources. Enable by adding the fully-qualified id to `settings.plugins.enabled` in `home-modules/noctalia.nix`:

```nix
settings.plugins.enabled = [
  "noctalia/screen_recorder"
  "me/hello"
];
```

Plugin options (e.g. wallhaven API key, screen_recorder settings) are edited in Settings → Plugins and persist to `~/.local/state/noctalia/settings.toml`; use the `noctalia-sync` skill to fold those back into the repo. For a plugin you are developing locally, prefer the data-dir drop-in above instead of packaging it in the flake. Reference implementations worth reading: `example` (widget/service/shortcut + panel), `timer` (desktop widget), `screen_recorder`, `wallhaven` in `github:noctalia-dev/official-plugins`.

## Full reference

Read `reference/plugin-development.md` for the exhaustive API tables: manifest + settings schema, entry lifecycle globals, `barWidget.*`/`shortcut.*`/`launcher.*`, the full `ui.*` control vocabulary, all `noctalia.*` runtime methods, plugin API version table, and publishing/catalog metadata.
