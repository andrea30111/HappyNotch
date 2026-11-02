# Notchy

A notch-native productivity companion for macOS 14+ (Apple Silicon). Hover the notch or press **⌥N** to open a compact panel with tasks, a focus timer, a daily notepad and today's events. A row of floating tool icons sits under the panel.

## Build & run

```sh
scripts/build-app.sh            # release build → build/Notchy.app (ad-hoc signed)
open build/Notchy.app
swift test                      # parser, streaks, HTTP parsing
```

Set `CODESIGN_IDENTITY="Developer ID Application: …"` to sign for distribution. Permissions (Calendar, Reminders, Microphone, Speech, Screen Recording for clips) are requested the first time each feature is used.

## Architecture (MVVM)

| Layer | Where | Notes |
| --- | --- | --- |
| Models | `Models/` | Codable value types; JSON with forward-compatible decoding |
| Persistence | `Persistence/Store.swift` | `~/Library/Application Support/Notchy/data.json`, debounced atomic writes, JSON export/import |
| Services (view models) | `Services/` | `FocusTimer`, `SpeechService`, `CalendarService` (read-only), `RemindersSync`, `AppleNotesSync`, `ClipService`, `ClipboardHistory`, `ReminderScheduler`, `HotKeyManager` |
| Notch window | `Notch/` | Non-activating `NSPanel` above the menu bar; hover via event monitors, so the menu bar is never blocked |
| Views | `Views/` | SwiftUI cards, floating `ToolDock`, week planner, insights (Swift Charts), settings, dashboard |
| MCP | `MCP/` | Loopback HTTP server (Streamable HTTP, JSON responses) plus a `--mcp-stdio` bridge |

## Keyboard

⌥N open/close · ⌘1…⌘9 switch tool · ⌘N new task · ⇧⌘M dictate · ⌘T start/pause focus · ⇧⌘C capture clip · ⌘D dashboard · ⌘↩ (notepad) line → task · Esc close

## URL scheme

`notchy://open?tool=week`, `notchy://add?text=call%20mom%20tomorrow%20at%205pm`, `notchy://dashboard`, `notchy://capture`

## AI agents (MCP)

Enable in **Customize › AI Agents** (off by default). The server binds to `127.0.0.1` and requires a bearer token; requests with a non-local `Origin` are rejected. Settings has copy buttons for both configs:

```json
{ "mcpServers": { "notchy": { "command": "/Applications/Notchy.app/Contents/MacOS/Notchy", "args": ["--mcp-stdio"] } } }
```

Tools: `list_tasks`, `add_task`, `complete_task`, `update_task`, `get_notepad`, `append_to_notepad`, `list_events` (read-only), `get_focus_status`, `start_focus`, `pause_focus`, `resume_focus`, `stop_focus`, `get_insights`.

## Apple Notes

Opt-in (Settings › Apple Calendar, Reminders & Notes). Each notepad day is mirrored two-way to a note titled `Notchy · yyyy-MM-dd` in a `Notchy` folder of the default Notes account, via AppleScript (requires the Automation permission). If both sides changed since the last sync, the notepad wins. Notes outside that folder are never read or modified.
