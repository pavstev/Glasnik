# AGENTS.md — setup instructions for AI agents

This file tells any AI agent (Cursor, Claude Code, Windsurf, …) how to set up Glasnik on
a user's Mac. **If a user hands you a link to this repo and asks you to "install / set up
Glasnik", follow the _Install_ section below — it's fully scripted.**

Glasnik is a macOS 14+ menu bar app: record Serbian → on-device WhisperKit transcription →
English (Ollama polish when available). Distributed via GitHub Releases, ad-hoc signed.

## Install (do this when asked to set up the app)

The installer cleans up any prior install, downloads the latest release, strips the
Gatekeeper quarantine (the app is ad-hoc signed, not notarized), installs to
`/Applications`, and launches it:

```sh
git clone https://github.com/pavstev/Glasnik.git
cd Glasnik
./scripts/install.sh
```

No clone needed:

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/Glasnik/main/scripts/install.sh | bash
```

Then tell the user:
- On first launch macOS asks for **microphone** access — they must **Allow** it.
- First launch downloads a **~2.9 GB** Whisper model (one time); the popover shows "Preparing model…".
- The app lives in the **menu bar** (a **Г** glyph), with **no Dock icon**.
- Default hotkey is **⌥⇧Space** (start/stop recording from anywhere).
- *Optional*, for polished translations: `brew install ollama && ollama pull qwen2.5:3b && ollama serve`.

Requirements: macOS 14+, and `curl` + `python3` (preinstalled on macOS). Nothing else.

## Clean slate (precondition)

`install.sh` runs this automatically, but you can run it directly to fully reset:

```sh
./scripts/cleanup.sh            # quit + uninstall the app, clear build artifacts
./scripts/cleanup.sh --purge    # ALSO delete saved history + the downloaded model
```

## Build from source (no Xcode required)

```sh
xcode-select --install   # if the Command Line Tools aren't present
./bundle.sh              # swift build + assemble & ad-hoc sign Glasnik.app
open Glasnik.app
```

## Conventions & gotchas (if you edit the code)

- **No full Xcode** — build with `swift build` / `./bundle.sh`. Do **not** add anything
  that needs an Xcode-only macro plugin: it won't compile under the Command Line Tools.
  This already bit `SwiftData` (`@Model`/`@Query`), Swift Testing (`import Testing`), and
  `#Preview`. (History therefore uses a JSON store; tests use `XCTest` and run in CI.)
- **Swift 6 language mode is on** — preserve the `actor` / `@MainActor` isolation.
- Global hotkey is **⌥⇧Space** via Carbon `RegisterEventHotKey`.
- Ad-hoc signed, non-sandboxed, local-only. Releases are tag-triggered: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- Always verify a change with `./bundle.sh` then launch — it's a menu-bar agent (no Dock icon).
