# Noctalia v5 — Complete Settings Reference

Source: `github:noctalia-dev/noctalia/cachix` pinned at `b7cbb0d0349eff7c10813bccd310d6786b402255` (2026-08-08).
Extracted from `src/config/schema/config_schema.cpp`, `src/config/config_types.h`, `example.toml`, the bar widget factory (`src/shell/bar/widget_factory.cpp`) and plugin manifests.

All of this maps onto `programs.noctalia.settings` (Nix attrset → TOML). Most changes hot-reload via inotify; startup-only settings are noted inline.

## Type legend

- `bool` boolean; `str` string; `int` integer; `float` accepts float or int
- `enum` string restricted to listed values (unrecognized value warns + keeps default)
- `color` ColorSpec: role token (`on_surface`, `surface_variant`, `outline`, `primary`, `secondary`, `error`, `hover`) or hex `#rrggbb[aa]`
- `path` string path, `~`/`$VAR` expanded; `str[]` array of strings; `map(str→str)` sub-table of strings; `table` nested sub-table
- Range-bound numbers are clamped at parse time; `step` is GUI metadata only
- Unknown keys produce an "unknown setting" warning; `[wallpaper]` `default`/`last`/`monitors`/`favorite` are app-managed state (exempt)

## Top-level sections

Schema-backed: `storage`, `shell`, `accessibility`, `wallpaper`, `theme`, `backdrop`, `lockscreen`, `notification`, `osd`, `system`, `weather`, `calendar`, `audio`, `brightness`, `battery`, `nightlight`, `location`, `idle`, `keybinds`, `dock`, `hot_corners`, `control_center`, `plugins`, `hooks`.
Custom root keys: `bar`, `widget`, `desktop_widgets`, `lockscreen_widgets`, `plugin_settings`, `include`, `config_version`, `config`.

---

## `[storage]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `key_source` | enum | `"secret-service"` | `secret-service` \| `file`. `file` requires `key_file` |
| `key_file` | path | `""` | Required + absolute when `key_source = "file"`; error if set with secret-service |

## `[shell]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `corner_radius_scale` | float | `1.0` | 0–2 (0 = square, 2 = extra rounded) |
| `button_borders` | bool | `true` | |
| `input_borders` | bool | `true` | |
| `popup_borders` | bool | `true` | |
| `popup_shadows` | bool | `true` | |
| `card_borders` | bool | `true` | |
| `font_family` | str | `"sans-serif"` | |
| `lang` | str | `""` | Empty = auto-detect from locale |
| `time_format` | str | `"{:%H:%M}"` | |
| `date_format` | str | `"%A, %x"` | |
| `offline_mode` | bool | `false` | Block all outgoing HTTP |
| `panel_anchor_bar` | str | `""` | Bar panels attach to without a source bar; empty = first enabled bar |
| `external_ip_enabled` | bool | `false` | Show WAN IP in Control Center network tab |
| `telemetry_enabled` | bool | `false` | |
| `setup_wizard_enabled` | bool | `true` | |
| `niri_overview_type_to_launch_enabled` | bool | `false` | |
| `polkit_agent` | bool | `false` | |
| `password_style` | enum | `"default"` | `default` \| `random` |
| `settings_show_advanced` | bool | `true` | |
| `settings_window_translucent` | bool | `false` | |
| `show_location` | bool | `true` | Hide weather location text |
| `app_icon_colorize` | bool | `false` | |
| `app_icon_color` | color | unset | |
| `launch_apps_as_systemd_services` | bool | `false` | |
| `launch_apps_custom_command` | str | `""` | |
| `clipboard_enabled` | bool | `true` | |
| `clipboard_keep_from_closed_apps` | bool | `true` | |
| `clipboard_history_max_entries` | int | `100` | 10–10000 |
| `clipboard_confirm_clear_history` | bool | `true` | |
| `screen_time_enabled` | bool | `false` | |
| `shared_gl_context` | bool | `true` | startup-only |
| `disable_mipmaps` | bool | `false` | |
| `clipboard_auto_paste` | enum | `"auto"` | `off` \| `auto` \| `ctrl_v` \| `ctrl_shift_v` \| `shift_insert` |
| `clipboard_image_action_command` | str | `""` | e.g. `gimp {path}` |
| `avatar_path` | path | `""` | |

### `[shell.animation]`
`enabled` bool (`true`), `speed` float (`1.0`, 0.1–4.0)

### `[shell.shadow]`
`direction` enum (`"down"`; `center`/`up`/`down`/`left`/`right`/`up_left`/`up_right`/`down_left`/`down_right`), `alpha` float (`0.55`, 0–1)

### `[shell.panel]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `transparency_mode` | enum | `"solid"` | `solid` \| `soft` \| `glass` |
| `borders` | bool | `true` | |
| `shadow` | bool | `true` | |
| `list_item_background` | bool | `false` | |
| `floating_layer` | enum | `"overlay"` | `top` \| `overlay` |
| `launcher_placement` | enum | `"floating"` | `attached` \| `floating` |
| `clipboard_placement` | enum | `"floating"` | `attached` \| `floating` |
| `control_center_placement` | enum | `"attached"` | `attached` \| `floating` |
| `wallpaper_placement` | enum | `"attached"` | `attached` \| `floating` |
| `session_placement` | enum | `"attached"` | `attached` \| `floating` |
| `polkit_placement` | enum | `"floating"` | `attached` \| `floating` |
| `launcher_position` | str | `"center"` | `auto`/`center`/`top_left`/`top_center`/`top_right`/`center_left`/`center_right`/`bottom_left`/`bottom_center`/`bottom_right` |
| `clipboard_position` | str | `"center"` | same vocabulary |
| `control_center_position` | str | `"auto"` | same vocabulary |
| `wallpaper_position` | str | `"auto"` | same vocabulary |
| `session_position` | str | `"auto"` | same vocabulary |
| `polkit_position` | str | `"center"` | same vocabulary |
| `floating_offset` | int | `8` | 0–100 |
| `open_near_click_control_center` | bool | `false` | |
| `open_near_click_launcher` | bool | `false` | |
| `open_near_click_clipboard` | bool | `false` | |
| `open_near_click_wallpaper` | bool | `false` | |
| `open_near_click_session` | bool | `false` | |

### `[shell.launcher]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `categories` | bool | `true` | |
| `show_icons` | bool | `true` | |
| `compact` | bool | `false` | |
| `app_grid` | bool | `false` | |
| `sort_by_usage` | bool | `true` | |
| `fetch_exchange_rates` | bool | `true` | |
| `provider_prefix` | str | `"/"` | trigger-word prefix |
| `auto_paste` | enum | `"auto"` | `off`/`auto`/`ctrl_v`/`ctrl_shift_v`/`shift_insert` |
| `dmenu` | table | — | `[shell.launcher.dmenu.entry.<id>]` (below) |
| `providers.<name>` | table | — | `prefix` str (default `""`), `global` bool. Providers: `calculator`, `emoji`, `session`, `wallpaper`, `windows` |

**dmenu entry** (`[shell.launcher.dmenu.entry.<id>]`): `command` str (shell; stdout lines = candidates), `exec` str (substitute `{selection}`/`{query}`; unset = copy selection), `prefix` str (trigger word), `label` str, `glyph` str (default `terminal`), `global` bool, `freeform` bool.

### `[shell.keyboard_layout]`
`custom_labels` map(str→str): override display labels by exact layout name.

### `[shell.screen_corners]`
`enabled` bool (`false`), `size` int (`32`, 1–100)

### `[shell.mpris]`
`blacklist` str[] — ignore MPRIS players by bus/identity/desktop-entry token.

### `[shell.screenshot]`
`save_to_file` (`true`), `copy_to_clipboard` (`true`), `freeze_screen` (`true`), `confirm_region` (`false`), `remember_last_region` (`false`), `show_cursor` (`false`), `pipe_to_command` (`false`), `pipe_command` (str), `directory` (str, empty = `~/Pictures`), `filename_pattern` (str, empty = `screenshot_%Y%m%d_%H%M%S`).

### `[shell.privacy]`
`mic_filter_regex`, `cam_filter_regex`, `screen_filter_regex` (all str, `""`).

### `[shell.session]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `actions` | array of tables | 5 defaults | each `{action, enabled, command, label, glyph, variant, shortcut, countdown_seconds}` |
| `grid` | bool | `false` | |
| `grid_columns` | int | `3` | 1–5 |
| `show_shortcuts` | bool | `true` | |
| `power` | table | — | `suspend`/`reboot`/`shutdown` optional str; empty = auto-detect backend |

**action** allowed values: `lock`, `logout`, `suspend`, `lock_and_suspend`, `reboot`, `shutdown`, `command`. `variant`: `default`/`primary`/`secondary`/`destructive`/`outline`/`ghost`. Defaults: lock(`1`), logout(`2`), lock_and_suspend(`3`), reboot(`4`), shutdown(`5`, destructive).

### `[shell.greeter_sync]`
`auto_sync` bool (`false`), `privilege_command` str (shell prefix replacing `pkexec`/`run0`).

## `[accessibility]`
`ui_scale` float (`1.0`, 0.5–2.5), `high_contrast` bool (`false`).

## `[wallpaper]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `fill_mode` | enum | `"crop"` | `center` \| `crop` \| `fit` \| `stretch` \| `repeat` \| `span` |
| `fill_color` | color | unset | |
| `transition` | str[] | `["fade","wipe","disc","stripes","zoom","honeycomb"]` | empty → `fade` |
| `transition_duration` | int | `1500` | 100–30000 ms |
| `edge_smoothness` | float | `0.3` | 0–1 |
| `transition_on_startup` | bool | `false` | |
| `directory` | path | `""` | empty = `~/Pictures/Wallpapers` |
| `directory_light` | path | `""` | empty = directory |
| `directory_dark` | path | `""` | empty = directory |
| `per_monitor_directories` | bool | `false` | |
| `automation` | table | — | below |
| `monitor.<match>` | table | — | `enabled`, `fill_color`, `directory`, `directory_light`, `directory_dark` |

### `[wallpaper.automation]`
`enabled` (`false`), `interval_seconds` int (`1800`, 1–86400), `order` enum (`random` \| `alphabetical`), `recursive` bool (`true`).

## `[theme]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `source` | enum | `"builtin"` | `builtin` \| `wallpaper` \| `community` \| `custom` |
| `builtin` | str | `"Noctalia"` | `Ayu`, `Catppuccin`, `Dracula`, `Eldritch`, `Gruvbox`, `Kanagawa`, `Noctalia`, `Nord`, `Rosé Pine`, `Tokyo-Night` |
| `community_palette` | str | `"Oxocarbon"` | fetched from api.noctalia.dev |
| `custom_palette` | str | `""` | |
| `wallpaper_scheme` | str | `"m3-content"` | `m3-tonal-spot` \| `m3-content` \| `m3-fruit-salad` \| `m3-rainbow` \| `m3-monochrome` \| `vibrant` \| `faithful` \| `soft` \| `dysfunctional` \| `muted` |
| `mode` | enum | `"dark"` | `dark` \| `light` \| `auto` |
| `pure_black_dark` | bool | `false` | |
| `templates` | table | — | below |

### `[theme.templates]`
`enable_builtin_templates` (`true`), `builtin_ids` str[], `enable_community_templates` (`true`), `community_ids` str[], `custom_colors` map, `user.<id>` table.

**Built-in template ids** (`noctalia theme --list-templates`): `alacritty`, `btop`, `cava`, `emacs`, `foot`, `ghostty`, `gtk3`, `gtk4`, `helix`, `hyprland`, `kcolorscheme`, `kitty`, `labwc`, `mango`, `niri`, `qt`, `scroll`, `starship`, `sway`, `wezterm`. Community templates also cached (e.g. `spicetify`, `pywalfox`, `code`, `discord`, `telegram`, `zed`, `yazi`, `walker`, `fuzzel`, `vicinae`).

**User template** (`[theme.templates.user.<id>]`): `enabled` (`true`), `input_path`, `input_path_modes` `{dark, light}`, `output_path` str or str[], `output_path_dynamic` (`false`), `compare_to`, `colors_to_compare` (array of `{name, color}`), `pre_hook`, `post_hook`, `post_action`, `index` (`0`).

## `[backdrop]`
`enabled` (`false`), `blur_intensity` float (`0.5`, 0–1), `tint_intensity` float (`0.3`, 0–1).

## `[lockscreen]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `lock_before_suspend` | bool | `true` | logind PrepareForSleep |
| `fingerprint` | bool | `true` | |
| `allow_empty_password` | bool | `false` | |
| `blurred_desktop` | bool | `false` | needs wlr-screencopy |
| `blur_intensity` | float | `0.5` | 0–1 |
| `tint_intensity` | float | `0.3` | 0–1 |
| `wallpaper` | path | `""` | empty = desktop wallpaper |
| `monitors` | str[] | `[]` | empty = all |

## `[notification]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enable_daemon` | bool | `true` | |
| `show_app_name` | bool | `true` | |
| `show_actions` | bool | `true` | |
| `position` | str | `"top_right"` | `top_right`/`top_left`/`top_center`/`bottom_*`/`center_*` |
| `layer` | enum | `"top"` | `top` \| `overlay` |
| `scale` | float | `1.0` | 0.5–2.5 |
| `background_opacity` | float | `0.97` | 0–1 |
| `border` | bool | `true` | |
| `offset_x` | int | `20` | |
| `offset_y` | int | `8` | |
| `monitors` | str[] | `[]` | |
| `collapse_on_dismiss` | bool | `true` | |
| `history_retention_hours` | int | `0` | 0–8760 |
| `max_visible` | int | `0` | 0–20; 0 = unlimited |
| `filter_order` | str[] | emitted | exporter-written |
| `filter.<name>` | table | — | below |

**Filter** (`[notification.filter.<name>]`): `enabled` (`true`), `match` str (case-insensitive token), `match_content` str (regex on summary/body), `show_toast` (`true`), `save_history` (`true`), `play_sound` (`true`), `allow_permanent` (`true`), `override_duration` int, `allowed_urgencies` str[] (`low`/`normal`/`critical`; empty = all).

## `[osd]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `true` | master gate |
| `position` | str | `"top_center"` | screen-anchor vocabulary |
| `position_vertical` | str | `"top_center"` | when orientation = vertical |
| `orientation` | str | `"horizontal"` | `horizontal` \| `vertical` |
| `scale` | float | `1.0` | 0.5–2.5 |
| `background_opacity` | float | `0.97` | 0–1 |
| `border` | bool | `true` | |
| `offset_x` | int | `20` | ≥0 |
| `offset_y` | int | `8` | ≥0 |
| `monitors` | str[] | `[]` | |
| `kinds` | table | all `true` | below |

### `[osd.kinds]` (all bool, default `true`)
`volume`, `volume_output`, `volume_input`, `brightness`, `wifi`, `bluetooth`, `power_profile`, `caffeine`, `nightlight`, `dnd`, `lock_keys`, `keyboard_layout`, `media`, `privacy`, `keyboard_backlight`.

## `[system.monitor]`
`enabled` (`true`), `cpu_temp_sensor_path` (str), `cpu_poll_seconds` (`2.0`, 0 disables, else 1–120), `gpu_poll_seconds` (`5.0`), `memory_poll_seconds` (`2.0`), `network_poll_seconds` (`3.0`), `disk_poll_seconds` (`10.0`). Plus activity/critical thresholds per metric: `cpu_usage`, `cpu_temp`, `gpu_temp`, `gpu_usage`, `gpu_vram`, `ram_pct`, `swap_pct`, `disk_used_pct`, `disk_used`, `disk_free_pct`, `disk_free`, `net_rx`, `net_tx` (e.g. `cpu_usage_activity_threshold`, `cpu_usage_critical_threshold`), defaults from power profile.

## `[weather]`
`enabled` (`true`), `effects` (`true`), `refresh_minutes` (`30`, 5–240), `unit` enum `metric` \| `imperial` (default `"metric"`; **note: not** `celsius`/`fahrenheit`).

## `[calendar]`
`enabled` (`false`), `refresh_minutes` (`15`, 5–240), `account.<id>` table (id must be `[a-z0-9_]`): `type` (`"google"`/`"caldav"`), `name`, `color` (`#rrggbb`), `provider` (`"icloud"`/`"custom"`, caldav), `server_url`, `username`, `calendars` str[], `credential_source` enum (`secret-service`/`file`), `password_file` path.

## `[audio]`
`enable_overdrive` (`false`; 150% ceiling), `enable_sounds` (`false`), `sound_volume` (`0.5`, 0–1), `volume_change_sound` str, `notification_sound` str (empty = bundled sounds).

## `[brightness]`
`enable_ddcutil` (`false`), `sync_all_monitors` (`false`), `ignore_mmids` str[], `minimum_brightness` (`0.0`, 0–1), `monitor.<match>` table: `backend` enum (`auto`/`none`/`backlight`/`ddcutil`), `backlight_device` str.

## `[battery]`
`warning_threshold` int (`10`, 0–100; 0 disables), `device.<selector>` table: `warning_threshold` (0–100).

## `[nightlight]`
`enabled` (`false`), `force` (`false`), `temperature_day` (`6500`, 1000–25000, must be ≥ night+100), `temperature_night` (`4000`, 1000–25000).

## `[location]`
`auto_locate` (`false`; IP-based), `address` str (geocoded), `custom_schedule` (`false`), `sunset`/`sunrise` (`HH:MM`), `latitude`/`longitude` float.

## `[idle]`
`pre_action_fade_seconds` float (`2.0`, 0–120; 0 = immediate), `behavior_order` str[] (exporter-written), `behavior.<name>` table:
- `enabled` (`true`; default behaviors ship disabled), `timeout` float, `action` enum: `lock` \| `screen_off` \| `suspend` \| `lock_and_suspend` \| custom command string, `command` str, `resume_command` str, `lock_before_suspend` (`true`)

Default behaviors (all disabled): `lock` (600), `screen-off` (660, `screen_off`), `lock-and-suspend` (900, `lock_and_suspend`).

## `[keybinds]`
Each key is a chord string or array of chord strings (always emitted as array):
`validate` (`return`,`kp_enter`,`space`), `cancel` (`escape`), `left`/`right`/`up`/`down`, `tab_next` (`tab`), `tab_previous` (`shift+iso_left_tab`), `delete` (`del`), `copy` (`ctrl+c`), `save` (`ctrl+s`).

## `[dock]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | opt-in |
| `position` | enum | `"bottom"` | `top`/`bottom`/`left`/`right` |
| `active_monitor_only` | bool | `false` | |
| `icon_size` | int | `48` | 16–128 |
| `main_axis_padding` | int | `16` | 0–100 |
| `cross_axis_padding` | int | `8` | 0–100 |
| `item_spacing` | int | `6` | 0–100 |
| `background_opacity` | float | `0.88` | 0–1 |
| `border` | color | `outline` | |
| `border_width` | float | `0.0` | 0–20 |
| `radius` | int | `16` | seeds corners; 0–80 |
| `radius_top_left`/`radius_top_right`/`radius_bottom_left`/`radius_bottom_right` | int | `16` | 0–80 |
| `concave_edge_corners` | bool | `true` | |
| `margin_ends` | int | `0` | 0–500 |
| `margin_edge` | int | `0` | 0–100 |
| `shadow` | bool | `true` | |
| `show_running` | bool | `true` | |
| `auto_hide` | bool | `false` | |
| `smart_auto_hide` | bool | `false` | |
| `layer` | enum | `"top"` | `top` \| `overlay` |
| `reserve_space` | bool | `true` | |
| `active_scale` | float | `1.0` | 0.1–1.75 |
| `inactive_scale` | float | `0.85` | 0.1–1.0 |
| `magnification` | bool | `true` | |
| `magnification_scale` | float | `1.45` | 1.0–2.0 |
| `active_opacity` | float | `1.0` | 0–1 |
| `inactive_opacity` | float | `0.85` | 0–1 |
| `show_dots` | bool | `false` | |
| `show_instance_count` | bool | `true` | |
| `launcher_position` | enum | `"none"` | `none` \| `start` \| `end` |
| `launcher_icon` | str | `"grid-dots"` | Tabler glyph |
| `launcher_custom_image` | path | `""` | |
| `launcher_custom_image_colorize` | bool | `false` | |
| `pinned` | str[] | `[]` | desktop entry IDs |
| `monitors` | str[] | `[]` | empty = all |

## `[hot_corners]`
`enabled` (`false`), `delay_ms` int (`0`, 0–2000), `top_left`/`top_right`/`bottom_left`/`bottom_right` tables with `action` and `command`.

**Corner actions**: `none` (or empty), `launcher`, `control_center`, `overview`, `window_switcher`, `command` (runs the corner's `command` shell string).

## `[control_center]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `sidebar` | enum | `"compact"` | `full` \| `compact` \| `none` |
| `sidebar_section` | enum | `"compact"` | `full` \| `compact` \| `none` |
| `width` | int | `700` | 600–1200 |
| `show_shortcut_labels` | bool | `true` | |
| `hidden_tabs` | str[] | `[]` | |
| `calendar` | table | — | below |
| `shortcuts` | array of `{type}` | 6 defaults | up to 6; empty `type` dropped |

### `[control_center.calendar]`
`show_events_card` (`true`), `show_week_numbers` (`false`), `event_date_format` (`"%A %e %B"`), `event_time_format` (`"%H:%M"`).

**Shortcut `type` values** (17 built-in): `wifi`, `bluetooth`, `nightlight`, `notification`, `dark_mode`, `caffeine`, `audio`, `mic_mute`, `power_profile`, `media`, `weather`, `system`, `screen_time`, `keyboard_layout`, `wallpaper`, `session`, `clipboard`. Plugin shortcuts use the plugin's `author/plugin:entry` id (e.g. screen_recorder's is `noctalia/screen_recorder:toggle`). Defaults: `wifi`, `bluetooth`, `caffeine`, `nightlight`, `notification`, `power_profile`.

## `[plugins]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `source` | array of tables | 2 defaults | `[[plugins.source]]` below |
| `enabled` | str[] | `[]` | plugin ids `"author/plugin"` |
| `auto_update` | `"all"` \| `"enabled"` \| `"none"` | `"all"` | startup + every 6h (boolean deprecated) |

**Source**: `name` (required; `[A-Za-z0-9._-]`), `kind` enum (`git` \| `path`), `location` (URL or local path), `enabled` (`true`). Defaults: `official` = `github.com/noctalia-dev/official-plugins`, `community` = `github.com/noctalia-dev/community-plugins`.

### `[plugin_settings."author/plugin"]`
Open-ended per-plugin override map (depth ≤ 3); validated against each plugin's manifest at `config validate`.

## `[hooks]`
19 keys; each a single command string or array of strings: `started`, `wallpaper_changed`, `colors_changed`, `theme_mode_changed`, `session_locked`, `session_unlocked`, `logging_out`, `rebooting`, `shutting_down`, `wifi_enabled`, `wifi_disabled`, `bluetooth_enabled`, `bluetooth_disabled`, `battery_charging`, `battery_discharging`, `battery_plugged`, `battery_percentage_changed`, `power_profile_changed`.

## `[bar.<name>]` — named bars
`name` is the table key; `position` emitted/keyed outside the field schema. `bar.order` lists active bars.
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `true` | |
| `auto_hide` | bool | `false` | |
| `smart_auto_hide` | bool | `false` | |
| `show_on_workspace_switch` | bool | `true` | |
| `reserve_space` | bool | `true` | |
| `layer` | enum | `"top"` | `top` \| `overlay` |
| `thickness` | int | `34` | 10–300 |
| `background_opacity` | float | `1.0` | 0–1 |
| `border` | color | `outline` | |
| `border_width` | float | `0.0` | 0–20 |
| `radius` | int | `12` | 0–500 |
| `radius_top_left`/`radius_top_right`/`radius_bottom_left`/`radius_bottom_right` | int | `12` | 0–500 |
| `concave_edge_corners` | bool | `true` | |
| `margin_ends` | int | `100` | |
| `margin_edge` | int | `0` | floats bar when > 0 |
| `margin_opposite_edge` | int | `0` | |
| `padding` | int | `14` | |
| `widget_spacing` | int | `6` | |
| `shadow` | bool | `true` | |
| `contact_shadow` | bool | `false` | |
| `panel_overlap` | int | `1` | −2–3 |
| `capsule_thickness` | float | `0.76` | 0.1–1.0 |
| `scale` | float | `1.0` | 0.5–4.0 |
| `font_weight` | int | `500` | |
| `font_family` | str | unset | inherits `shell.font_family` |
| `start`/`center`/`end` | str[] | defaults below | widget references / `group:<id>` |
| `capsule` | bool | `false` | |
| `capsule_fill` | color | `surface_variant` | |
| `capsule_foreground` | color | unset | |
| `color` | color | unset | default label color |
| `icon_color` | color | unset | |
| `capsule_group` | array of tables | `[]` | |
| `capsule_padding` | float | `6` | 0–48 |
| `capsule_radius` | float | unset | 0–80; unset = auto pill |
| `capsule_opacity` | float | `1.0` | 0–1 |
| `capsule_border` | color | unset | |
| `hover_highlight` | bool | `true` | |
| `dead_zone` | table | — | `actions` map (gesture→action) |
| `actions` | map(str→str) | `{}` | gestures: `left`/`middle`/`right`/`back`/`forward`/`scroll_up`/`scroll_down` |
| `monitor.<match>` | table | — | per-monitor override of any bar key |

Default lanes: `start = ["launcher", "wallpaper", "workspaces"]`, `center = ["clock"]`, `end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]`.

**capsule_group element**: `id` (required), `enabled` (`true`), `members` str[], `fill` (`surface_variant`), `border`, `foreground`, `padding` (`6`, 0–48), `radius`, `opacity` (`1.0`), `accordion` (`false`), `accordion_direction` (`end`/`start`), `widget_spacing`.

## `[widget.<name>]` — bar widget instances
`type` (str; defaults to entry name) + settings. Plugin widgets: `type = "author/plugin:entry"`.

### Common settings (all widgets)
`enabled` (`true`), `anchor` (`false`), `interactive` (`true`), `scale` (`1.0`, 0.2–2.5), `color`, `icon_color`, `font_family`, `font_weight`, `capsule` (`false`), `capsule_radius`, `capsule_fill`, `capsule_border`, `capsule_foreground`, `capsule_padding` (`6`, 0–48), `capsule_opacity` (`1.0`), `scroll_repeat` enum (`auto`/`gesture`/`steps`), `actions` map, `enable_scroll` (`true`, plugins).

### Built-in widget types and settings

| Type | Type-specific settings |
|---|---|
| `clock` | `format` (`"{:%H:%M}"`), `vertical_format`, `tooltip_format`, `timezone` |
| `media` | `album_art_only` (`false`), `hide_album_art` (`false`), `hide_artist` (`false`), `artist_first` (`false`), `min_length` (`80`, 0–800), `max_length` (`220`, 40–800), `art_size` (`16`, 8–96), `title_scroll` enum `none`/`always`/`on_hover`, `hide_when_no_media` (`false`) |
| `active_window` | `min_length` (`80`), `max_length` (`260`, 40–800), `icon_size` (`14`, 8–64), `title_scroll` enum, `display` enum `icon_and_text`/`icon_only`/`text_only`, `show_empty_label` (`false`) |
| `battery` | `display_mode` enum `none`/`glyph`/`graphic`, `show_label` (`true`), `label_content` enum `percent`/`time`/`rate`, `hide_when_plugged` (`false`), `hide_when_full` (`false`), `device` (`"auto"`), `warning_color` (`error`) |
| `network` | `vpn_status` enum `replace`/`both`/`hidden`, `show_label` (`true`), `show_vpn_label` (`false`) |
| `sysmon` | `stat` enum (`cpu_usage`/`cpu_temp`/`gpu_temp`/`gpu_usage`/`gpu_vram`/`ram_used`/`ram_pct`/`swap_pct`/`disk_used_pct`/`disk_used`/`disk_free_pct`/`disk_free`/`net_rx`/`net_tx`), `path` (`"/"`), `interface`, `network_speed_unit` (`auto`/`kb`/`mb`), `network_speed_compact`, `visualization` enum `gauge`/`graph`/`none`, `show_value` (`true`), `label_show_units` (`true`), `label_min_width`, `show_glyph` (`true`), `glyph`, `custom_image`, `custom_image_colorize`, `glyph_position` (`before`/`after`), `highlight_color` (`error`) |
| `volume` | `device` enum `output`/`input`, `glyph`, `mute_glyph`, `effects_profile_glyphs` map, `custom_image`, `custom_image_colorize`, `show_label` (`true`), `mute_color` (`error`) |
| `brightness` | `show_label` (`true`) |
| `bluetooth` | `show_label` (`false`), `hide_when_no_connected_device` (`false`) |
| `workspaces` | `hide_when_empty` (`false`), `show_labels` (`true`), `label_source` (`id`/`name`), `labels_only_when_occupied` (`false`), `max_label_chars` (`1`, 1–20), `style` enum `regular`/`minimal`/`focus_hint`, `pill_scale`, `active_pill_size` (`2.2`), `inactive_pill_size` (`1.0`), `focused_output_only` (`false`), `change_color_on_hover` (`true`), `focused_color` (`primary`), `occupied_color` (`secondary`), `empty_color` (`secondary`), `urgent_color` (`error`) |
| `taskbar` | `show_all_outputs` (`false`), `show_active_indicator` (`true`), `active_indicator_color` (`primary`), `active_opacity`/`inactive_opacity` (`1.0`), `pinned` str[], `pinned_opacity` (`0.5`), `show_window_title` (`false`), `window_title_max_width` (`100`), `taskbar_max_width` (`8192`), `only_active_workspace`/`group_by_workspace`/`hide_empty_workspaces`, `workspace_group_content` (`icons`/`count`/`dots`), `group_single_icon_per_app`, `workspace_group_capsule` (`true`), `show_workspace_label` (`true`), `workspace_label_placement` (`corner`/`centered`/`inside`), `minimal`, `focused_output_only`, `focused_color`/`occupied_color`/`empty_color`/`urgent_color` |
| `tray` | `hidden` str[], `pinned` str[], `match_adjacent_spacing` (`false`), `drawer` (`false`), `drawer_columns` (`3`, 1–5), `drawer_item_size` (`16`, 8–64), `detached_panel` (`false`) |
| `notifications` | `hide_when_no_unread` (`false`) |
| `clipboard` / `control-center` / `launcher` / `wallpaper` / `session` / `settings` / `screenshot` | glyph-button: `glyph`, `custom_image`, `custom_image_colorize`. Default glyphs: `clipboard`, `noctalia`, `search`, `wallpaper-selector`, `shutdown`, `settings`, `screenshot` |
| `custom_button` | glyph-button + `label`, `tooltip` (default glyph `heart`) |
| `keyboard_layout` | `hide_when_single_layout` (`false`), `show_glyph` (`true`), `glyph` (`keyboard`), `custom_image`, `custom_image_colorize`, `show_label` (`true`), `display` (`short`/`full`) |
| `lock_keys` | `show_caps_lock` (`true`), `show_num_lock` (`true`), `show_scroll_lock` (`false`), `hide_when_off` (`false`), `display` (`short`/`full`) |
| `privacy` | `hide_inactive` (`false`), `icon_spacing` (`4`), `active_color` (`primary`), `inactive_color` (`outline`) |
| `audio_visualizer` | `width` (`56`, 8–2048), `bands` (`16`, 2–128), `mirrored` (`true`), `centered` (`true`), `show_when_idle` (`false`), `color_1`/`color_2` (`primary`) |
| `weather` | `max_length` (`160`, 40–800), `show_condition` (`true`), `show_temperature` (`true`) |
| `spacer` | `length` (`20`, 0–400); `interactive` defaults `false` |
| `text` | `text` (str) |
| `caffeine` / `nightlight` / `power_profile` / `theme_mode` / `test` | common settings only |

### Default gesture actions
- Universal: `middle` → `settings-open-widget`
- `battery`: left → `control-center power`; `bluetooth`: left → `control-center bluetooth`, right → `bluetooth-toggle`; `brightness`: left → `control-center monitor`, scroll → `brightness-up/down`; `clipboard`: left → `panel-toggle clipboard`; `clock`: left → `control-center calendar`; `control-center`: left → `control-center home`; `launcher`: left → `panel-toggle launcher`; `network`: left → `control-center network`, right → `network-toggle`; `caffeine`: left → `caffeine-toggle`; `keyboard_layout`: left → `keyboard-layout-cycle`; `media`: left → `control-center media`, right → `media toggle`, back/forward → prev/next, scroll → next/prev; `nightlight`: left → `nightlight-toggle`, right → `nightlight-force-toggle`; `notifications`: left → `control-center notifications`, right → `notification-dnd-toggle`; `power_profile`: left/scroll_up → `power-cycle next`, right/scroll_down → `power-cycle prev`; `screenshot`: left → `screenshot-region`; `session`: left → `panel-toggle session`; `settings`: left → `settings-open`; `sysmon`: left → `control-center system`; `taskbar`: scroll → `taskbar-cycle prev/next`; `theme_mode`: left → `theme-mode-toggle`; `volume` (output): left → `control-center audio`, right → `volume-mute`, scroll → `volume-up/down`; (input): right → `mic-mute`, scroll → `mic-volume-up/down`; `wallpaper`: left → `panel-toggle wallpaper`; `weather`: left → `control-center weather`; `workspaces`: scroll → `workspace-switch prev/next`
- Reserved (not bindable): workspaces left; taskbar left/middle; tray left/right; screenshot right

## `[desktop_widgets]` / `[lockscreen_widgets]`
| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `true` (desktop) / `false` (lockscreen) | |
| `schema_version` | int | `2` | |
| `grid` | table | — | `visible` (`true`), `cell_size` (`16`, 8–256), `major_interval` (`4`, 1–16) |
| `widget_order` | str[] | emitted | active widget list + stacking |
| `widget.<name>` | table | — | below |

**Widget instance**: `id`, `type` (`"clock"`), `output` (connector), `cx`/`cy` float, `box_width`/`box_height` float (0 = auto-fit), `rotation`, `flip_x`/`flip_y`, `enabled` (`true`), `settings` table.

**Desktop/lockscreen widget types**: `clock`, `audio_visualizer`, `fancy_audio_visualizer`, `sticker`, `weather`, `media_player`, `label`, `button`, `sysmon`, `volume`, plugin widgets, and `login_box` (lockscreen only).

**Common background settings** (most types): `background` (`true`), `background_color` (`surface`), `background_radius` (`12`, 0–32), `background_padding` (`10`, 0–32), `background_opacity` (`0.8`, 0–1).

Per-type highlights:
- **clock**: `clock_style` (`digital`/`analog`), `format`, `center_text`, `timezone`, `color`, `font_family`, `shadow`, `circle`
- **audio_visualizer**: `bands` (`32`, 4–128), `mirrored`, `centered`, `show_when_idle`, `color_1`/`color_2`
- **fancy_audio_visualizer**: `visualization_mode` (`bars`/`wave`/`rings`/`bars_rings`/`wave_rings`/`all`), `sensitivity`, `rotation_speed`, `bar_width`, `wave_thickness`, `ring_opacity`, `inner_diameter`, `bloom_intensity`, `fade_when_idle`, `primary_color`/`secondary_color`
- **sticker**: `image_path`, `opacity`
- **weather**: `color`, `font_family`, `shadow`, `show_forecast`, `forecast_days` (`3`, 1–6)
- **media_player**: `layout` (`horizontal`/`vertical`), `color`, `font_family`, `shadow`, `hide_when_no_media`
- **label**: `title`, `description`, `color`, `opacity`, `font_family`, `shadow`
- **button**: `glyph`, `label`, `command`, `variant`, `color`, `hover_background`, `font_family`
- **sysmon**: `stat`, `stat2`, `interface`, `network_speed_unit`, `network_speed_compact`, `display` (`graph`/`gauge`), `gauge_layout`, `color`, `color2`, `highlight_color`, `font_family`, `show_label`, `label_min_width`, `shadow`
- **volume**: `device`, `glyph`, `fill_color`, `track_color`, `show_device`, `scroll_step`, `font_family`, `shadow`
- **login_box**: `layout` (`compact`/`regular`), `show_session_buttons`, `show_media`, `show_weather`, `show_login_button`, `show_unlock_hint`, `show_caps_lock`, `show_keyboard_layout`, `input_opacity`, `input_radius`, `center_password_text`

## Discovery commands

```bash
noctalia config validate            # TOML syntax, unknown keys, bad values (exit 1 on error)
noctalia config export merged       # active merged user config as TOML
noctalia config export full         # all settings including defaults
noctalia config settings-count      # Settings UI controls by registry/section
noctalia msg plugins list           # every plugin (official + community) with version + enabled state
noctalia theme --list-templates     # all built-in + cached community template ids
noctalia msg brightness-list-backlight-devices   # sysfs backlight names for brightness.monitor
noctalia msg plugins enable|disable|update <id>
```

## Known gotchas

- **Weather `unit`** is `metric`/`imperial`, not `celsius`/`fahrenheit`.
- **Plugin entries** are addressed as `author/plugin:entry` (e.g. screen_recorder widget = `noctalia/screen_recorder:recorder`, its control-center shortcut = `noctalia/screen_recorder:toggle`). A bare name like `screen_recorder` does not resolve.
- **Idle behaviors** are named tables (`lock`, `screen-off`, `lock-and-suspend` defaults); `behavior_order` is exporter-managed.
- The `cachix` flake input is pinned to the latest commit with prebuilt binaries; do not add `inputs.nixpkgs.follows`.
- GUI overrides persist to `~/.local/state/noctalia/settings.toml` and layer over the declarative config.
