# AGENTS.md — setup instructions for AI agents

This file tells any AI agent (Cursor, Claude Code, Windsurf, …) how to set up Šapat on
a user's Mac. **If a user hands you a link to this repo and asks you to "install / set up
Šapat", follow the _Install_ section below — it's fully scripted.**

Šapat is a macOS 14+ menu bar app: record Serbian → on-device WhisperKit transcription →
English (LM Studio refinement when available). Distributed via GitHub Releases, ad-hoc signed.

## Install (do this when asked to set up the app)

The installer cleans up any prior install, downloads the latest release, strips the
Gatekeeper quarantine (the app is ad-hoc signed, not notarized), installs to
`/Applications`, and launches it:

```sh
git clone https://github.com/pavstev/Sapat.git
cd Sapat
./scripts/install.sh
```

No clone needed:

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/Sapat/main/scripts/install.sh | bash
```

Then tell the user:
- On first launch macOS asks for **microphone** access — they must **Allow** it.
- First launch downloads a **~2.9 GB** Whisper model (one time); the popover shows "Preparing model…".
- The app lives in the **menu bar** (a **Ш** glyph), with **no Dock icon**.
- Default hotkey is **⌥⇧Space** (start/stop recording from anywhere).
- *Optional*, for refined translations: `brew install --cask lm-studio && lms get qwen3-8b --mlx && lms server start` (OpenAI-compatible API on :1234).

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
./bundle.sh              # swift build + assemble & ad-hoc sign Sapat.app
open Sapat.app
```

## Conventions & gotchas (if you edit the code)

- **No full Xcode** — build with `swift build` / `./bundle.sh`. Do **not** add anything
  that needs an Xcode-only macro plugin: it won't compile under the Command Line Tools.
  This already bit `SwiftData` (`@Model`/`@Query`), Swift Testing (`import Testing`), and
  `#Preview`. (History therefore uses a JSON store; tests use `XCTest` and run in CI.)
- **Swift 6 language mode is on** — preserve the `actor` / `@MainActor` isolation.
- Refinement is via LM Studio's OpenAI-compatible API (`:1234`); `LMStudioClient` works with
  any OpenAI-compatible local server and falls back to Whisper's offline translate when down.
- Global hotkey is **⌥⇧Space** via Carbon `RegisterEventHotKey`.
- Ad-hoc signed, non-sandboxed, local-only. Releases are tag-triggered: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- Always verify a change with `./bundle.sh` then launch — it's a menu-bar agent (no Dock icon).

## Continuing on a new machine (or a fresh Claude)

Everything needed lives in this repo — Git is the source of truth, there is no external
state. To pick development back up on another Mac:

1. **Prereqs:** macOS 14+, Command Line Tools (`xcode-select --install`), `git`, `gh`.
2. **Identity:** `gh auth login` (GitHub account **pavstev**), then
   `git config user.name pavstev && git config user.email pavstev@users.noreply.github.com`.
3. `git clone https://github.com/pavstev/Sapat.git && cd Sapat`
4. Build + run: `./bundle.sh && open Sapat.app` (first launch re-downloads the ~2.9 GB model).
5. Read the **Conventions & gotchas** above before editing. History is in the commit log;
   in-flight work is in GitHub issues/PRs.

Identity facts: bundle id `com.stevanpavlovic.Sapat`; no Apple Developer account
(ad-hoc signing); no full Xcode (build via SwiftPM/CLT). Names, paths, and the repo slug
all derive from `Sources/Brand.swift` — change identity there, not scattered literals.

## Project status & roadmap

- **Shipped:** Šapat rebrand (name/icon/bundle/repo from `Brand.swift`), copper-on-stone UI,
  automatic GitHub updates (download → checksum-verify → in-place swap → relaunch), concise
  collapsible history, LM Studio (Qwen3-8B MLX) refinement with a dedup / no-fabrication /
  output-only prompt + conservative sanitizer, and long-form VAD silence tuning.
- **Deferred backlog** (good next tasks): a quit-mid-transcription guard
  (`applicationShouldTerminate` while busy); a real download/transcribe progress bar wired
  into `AppState.preparing(progress:)`; load the recorded audio once to avoid a second
  WhisperKit encode on the LM-Studio-down fallback path.
- **Cut a release:** `git tag vX.Y.Z && git push origin vX.Y.Z` → CI builds + publishes the
  GitHub Release; the in-app updater and `scripts/install.sh` pick it up automatically.
