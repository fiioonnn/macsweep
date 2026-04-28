# 🧹 macsweep

A no-bullshit Mac cleanup tool. Single bash file, zero dependencies, gives you control over what gets deleted.

Scans for caches, build artifacts, and logs across package managers, IDEs, browsers, apps, and Docker. You pick what to nuke. Then it nukes it.

## Quick start

Run it once without installing:

```bash
curl -sL https://raw.githubusercontent.com/fiioonnn/macsweep/main/macsweep.sh -o /tmp/macsweep.sh && bash /tmp/macsweep.sh
```

Or install it globally so you can just type `macsweep`:

```bash
curl -sL https://raw.githubusercontent.com/fiioonnn/macsweep/main/macsweep.sh -o /tmp/macsweep.sh && bash /tmp/macsweep.sh install
```

After install, run anytime with:

```bash
macsweep
```

## Commands

| Command | What it does |
|---|---|
| `macsweep` | Run interactive cleanup |
| `macsweep install` | Install to `/usr/local/bin/macsweep` |
| `macsweep update` | Pull the latest version from GitHub |
| `macsweep uninstall` | Remove from system |
| `macsweep version` | Print version |
| `macsweep help` | Show usage |

## What it cleans

- **Package managers** — npm, Yarn, pnpm, Composer, Gradle, Maven, pip, gem, CocoaPods, Homebrew, Cargo, Go modules, pub
- **Editors & IDEs** — VS Code, Cursor, JetBrains, Xcode (DerivedData, Archives, DeviceSupport, Simulator)
- **Browsers** — Arc, Chrome, Firefox, Safari, Brave, Edge, Opera caches
- **Apps** — Slack, Discord, Spotify, Figma, Postman, ClickUp, Zoom, Teams, Notion, Linear, Raycast, 1Password, Claude, Voicemod
- **Docker** — `docker system prune -af --volumes`
- **System** — temp files, log folders, crash reports, iOS device backups
- **Personal** *(opt-in, asked separately)* — Trash, Downloads

## How it works

1. Scans every known location and measures size with `du`.
2. Shows you everything found in a checkbox menu — you toggle what you want gone.
3. Asks for explicit `yes` confirmation before touching anything.
4. Runs cleanup with a live progress bar.

Sensitive folders (Trash, Downloads) are never selected by default — they live behind a separate prompt.

## Updates

macsweep checks GitHub for new releases on startup (in the background, ~3s timeout). If a new version exists, the menu shows:

```
⬆ Update available: v1.1.0 → v1.2.0 — press u to update now
```

Hit `u` to update on the spot, or run `macsweep update` anytime.

Skip the check entirely:

```bash
MACSWEEP_NO_UPDATE_CHECK=1 macsweep
```

## Requirements

- macOS (uses `du`, `find`, optional `brew` / `npm` / `docker`)
- `bash` (ships with macOS)
- `curl` (only needed for install / self-update)

## Uninstall

```bash
macsweep uninstall
```

Removes the binary from `/usr/local/bin`. Doesn't touch anything else.

## License

MIT
