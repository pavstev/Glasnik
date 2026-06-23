# Glasnik

A native macOS menu bar app that turns Serbian speech into polished English.

Press a global shortcut (or click the menu bar mic), speak Serbian, and Glasnik
transcribes it on‑device with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift),
translates it to English, shows both, and copies the English to your clipboard.

It's **offline‑first**: everything runs on your Mac. A local
[Ollama](https://ollama.com) model is used *if available* to polish the translation,
but the app works fully without it.

> *Glasnik* (гласник) — Serbian for "messenger".

## Install

1. Download the latest **`Glasnik-x.y.z.zip`** from the
   [Releases page](https://github.com/pavstev/Glasnik/releases/latest) and unzip it.
2. Move `Glasnik.app` to `/Applications`.
3. The app is **ad‑hoc signed** (no paid Apple Developer account), so on first launch
   Gatekeeper will balk. Either:
   - **Right‑click the app → Open → Open**, or
   - run once: `xattr -dr com.apple.quarantine /Applications/Glasnik.app`
4. Look for the **mic icon in the menu bar** (the app has no Dock icon).

On first launch Glasnik downloads the `openai_whisper-small` model (~250 MB) from
Hugging Face — the popover shows **"Preparing model…"** until it's ready, and macOS
prompts once for microphone access.

### Optional: polished translations with Ollama

```sh
brew install ollama        # or download from https://ollama.com
ollama pull qwen2.5:3b
ollama serve               # leave running
```

When Ollama is running, `qwen2.5:3b` produces cleaner English. Without it, Glasnik
falls back to Whisper's own translation (rougher) and tells you how to enable Ollama.

## How it works

```
record (16 kHz mono WAV)
   └─ WhisperKit  ──▶  Serbian transcript        (task: transcribe, language: sr)
        └─ translate:
             ├─ Ollama qwen2.5:3b  ──▶  polished English   (preferred, if running)
             └─ WhisperKit          ──▶  English baseline   (offline fallback, task: translate)
   └─ show Serbian + English, auto‑copy English to the clipboard
```

- Single, app‑level state machine: `preparing → idle → recording → transcribing → translating → done` (plus `error`).
- The model is prewarmed at launch and the microphone is requested up front.
- A no‑speech guard prevents Whisper from "hallucinating" text out of silence.
- The global hotkey uses Carbon's `RegisterEventHotKey` directly — no third‑party
  dependency, no extra permission.
- An in‑app **update check** queries GitHub Releases and shows a banner when a newer
  version is available.

## Usage

- **Click** the menu bar mic to open the popover, then click the big button to start/stop.
- **Global shortcut ⌥⌘G** starts/stops recording from any app and opens the popover
  for feedback (fixed for v1; rebinding is a planned enhancement).
- The mic icon turns **red** while recording. On completion the English is shown and
  **auto‑copied** to the clipboard (you'll see a "Copied ✓" confirmation).
- Use the **↻** button in the popover footer to check for updates manually.

## Build from source

You do **not** need full Xcode — Glasnik builds with the Command Line Tools via SwiftPM.

```sh
xcode-select --install     # if you don't already have the CLT
git clone https://github.com/pavstev/Glasnik.git
cd Glasnik
./bundle.sh                # swift build + assemble & ad-hoc sign Glasnik.app
open Glasnik.app
```

`bundle.sh` env overrides: `GLASNIK_VERSION=1.2.3` stamps a version into the bundle;
`GLASNIK_UNIVERSAL=1` builds a universal (arm64 + x86_64) binary.

### Building with Xcode instead (optional)

```sh
brew install xcodegen
xcodegen generate
open Glasnik.xcodeproj
```

## Releasing (maintainer)

Releases are **fully automated** by GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)):

```sh
# bump the version, then:
git tag v1.2.0
git push origin v1.2.0
```

The workflow builds on a macOS runner, runs `bundle.sh` (stamping the tag version),
zips the app with `ditto`, and publishes a GitHub Release with auto‑generated notes.
Every push/PR to `main` is also build‑checked by
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Translation quality

Whisper's offline translation quality scales with model size; bump `whisperModel` in
`Sources/RecorderViewModel.swift` to `openai_whisper-large-v3` (~1.5 GB) for better
offline results at the cost of a larger download and more latency.

## Project layout

| File | Responsibility |
| --- | --- |
| `Package.swift` | SwiftPM build (CLT, no Xcode) — primary build path |
| `bundle.sh` | Builds + assembles & ad‑hoc signs `Glasnik.app` |
| `project.yml` | Optional XcodeGen spec (only if you use full Xcode) |
| `.github/workflows/ci.yml` | Build check on push/PR |
| `.github/workflows/release.yml` | Tag‑triggered build + GitHub Release |
| `Info.plist` | `LSUIElement`, `NSMicrophoneUsageDescription`, bundle metadata |
| `Sources/GlasnikApp.swift` | `@main`; app delegate adaptor + Settings scene |
| `Sources/AppDelegate.swift` | Status item, popover, global hotkey, status‑icon updates |
| `Sources/RecorderViewModel.swift` | `@Observable @MainActor` — all recording/translation logic |
| `Sources/UpdateChecker.swift` | GitHub Releases update check |
| `Sources/WhisperEngine.swift` | WhisperKit wrapper (transcribe + translate passes) |
| `Sources/OllamaClient.swift` | Local Ollama `/api/generate` client + typed errors |
| `Sources/PopoverView.swift` | SwiftUI popover (record button, transcript, status, hints, update banner) |
| `Sources/SettingsView.swift` | Preferences window |
| `Sources/AppState.swift` | State machine + error/hint/action models |
| `Sources/GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper + ⌥⌘G default |

## Notes & limitations

- First run blocks on the model download; subsequent launches load from cache.
- Releases are ad‑hoc signed (not notarized) — see the Gatekeeper step in **Install**.
- The offline (Whisper‑small) translation is rougher than Ollama's polish.
- Released binaries are arm64 (Apple Silicon); set `GLASNIK_UNIVERSAL=1` to build universal.
- The global shortcut is fixed at ⌥⌘G for v1.
- Bundle id: `com.stevanpavlovic.Glasnik`.

## Dependencies

- [argmax-oss-swift / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — on‑device speech (pinned to 1.0.0)
- [Ollama](https://ollama.com) + `qwen2.5:3b` — optional translation polish
