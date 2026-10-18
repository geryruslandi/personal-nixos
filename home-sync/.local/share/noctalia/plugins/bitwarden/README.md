# Bitwarden (`gery/bitwarden`)

A Raycast-style [Bitwarden](https://bitwarden.com/) client for the Noctalia
launcher, driven by the official `bw` CLI. Replaces the bundled
`noctalia/bitwarden` plugin: instead of a single "copy the configured field"
action it exposes the full per-item action surface of the Raycast extension.

## Usage

Type `/bw` in the launcher:

| Query | What you get |
|---|---|
| `/bw` | Root actions + all vault items (favorites first, searchable by name/username/URI/folder) |
| `/bw github` | Fuzzy vault search |
| `/bw item:<id>` | Per-item actions: Show Details, Copy/Paste Password, Copy/Paste TOTP, Copy/Paste Username, Open in Browser, URI copies, Show/Copy Notes, Favorite, vault actions |
| `/bw details:<id>` | Every field of the item; Enter copies the field value |
| `/bw auth` | Live TOTP codes (computed locally, updates every second) |
| `/bw gen` | Generated password with regenerate/copy/paste |
| `/bw sends` | Bitwarden Sends: copy link, edit, delete, remove password |

Panels cover the rest: Unlock vault, Log in with API key, master-password
reprompt for protected items, password/passphrase generator, Create Login,
Create Folder, Create/Edit Send, Receive Send and a long-text viewer.

## Behaviour

- The service is the only owner of the `bw` process and session token; the
  launcher and panels talk to it over an in-memory request/response channel.
- Vault timeout: lock on shell restart (default), after N minutes of
  inactivity, or never — same options as the official plugin.
- Passwords/TOTP codes (and any field marked hidden) copied to the clipboard
  are cleared again after `clear_clipboard_seconds` (default 30s) if still
  unchanged. "Paste" types the value into the focused window with `wtype`
  (falls back to copying when unavailable) so secrets never need to touch the
  clipboard at all.
- Items with Bitwarden's "master password re-prompt" require the master
  password again before their secrets can be copied (verified by
  re-unlocking, disableable in the settings).
- The vault is synced on unlock and whenever it is older than
  `auto_sync_minutes` (default 15) while browsing; `Sync Vault` is always
  available in the root actions.

## Dependencies

- `bitwarden-cli` (the `bw` binary)
- `wtype` for pasting into the focused window (optional)

## Notes

- TOTP codes are computed locally (HMAC-SHA1 / HMAC-SHA256, Steam Guard
  encoding); SHA512 keys fall back to `bw get totp`.
- Favorites are local to this plugin (like Raycast's), stored in the plugin
  data dir; Bitwarden-side favorites are displayed with a ★ too.
- Every `bw` subprocess runs with
  `NODE_OPTIONS=--no-network-family-autoselection` (appended to any existing
  NODE_OPTIONS). Node ≥ 20's happy-eyeballs aborts the whole request when a
  host has an IPv6 default route but no global IPv6 address (dual-stack hosts
  like identity.bitwarden.com then fail with `FetchError … reason:` and an
  empty cause) instead of falling back to IPv4.
