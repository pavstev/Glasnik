<p align="center">
  <img src="docs/icon.png" width="128" alt="Glasnik icon — ГG monogram">
</p>

<h1 align="center">Glasnik</h1>

<p align="center">A native macOS menu bar app that turns Serbian speech into polished English — on‑device.</p>

<p align="center">
  <a href="https://github.com/pavstev/Glasnik/actions/workflows/ci.yml"><img src="https://github.com/pavstev/Glasnik/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/pavstev/Glasnik/releases/latest"><img src="https://img.shields.io/github/v/release/pavstev/Glasnik?sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/pavstev/Glasnik" alt="MIT"></a>
</p>

---

Press a shortcut (or click the menu bar **Г**), speak Serbian, and Glasnik transcribes
it on‑device with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), translates
it to English, shows both, and copies the English to your clipboard.

It's **offline‑first**: everything runs on your Mac. A local [Ollama](https://ollama.com)
model polishes the translation *if available*, but the app works fully without it.

> *Glasnik* (гласник) — Serbian for "messenger". The icon is **ГG** — the letter *G* in both alphabets.

## Features

- 🎙️ **On‑device transcription** — WhisperKit `large-v3` with VAD chunking for accurate, long‑form Serbian.
- ✨ **Polished translation** — local Ollama `qwen2.5:3b` when running; Whisper's own translate task as an offline fallback.
- 🌊 **Live waveform** — the menu bar **Г** animates with your voice while recording.
- 🗂️ **Searchable history** — every translation saved locally, searchable, re‑copyable (Record / History toggle).
- 🎚️ **Tone & glossary** — pick a tone (polished / formal / casual / literal) and add a custom glossary.
- ⌨️ **Global hotkey** — `⌥⇧Space` from any app; the popover stays open across app and Space switches.
- ⬇️ **In‑app updates** — checks GitHub Releases and offers the latest.

## Install with an AI agent

Hand any AI agent (Cursor, Claude Code, …) a link to this repo and ask it to "set up
Glasnik" — it follows [`AGENTS.md`](AGENTS.md). Or run the one‑line installer yourself; it
cleans up any prior install, downloads the latest release, strips the Gatekeeper
quarantine, installs to `/Applications`, and launches:

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/Glasnik/main/scripts/install.sh | bash
```

To fully reset first (uninstall + optionally delete history/model):
`./scripts/cleanup.sh [--purge]`.

## Install (manual)

1. Download the latest **`Glasnik-x.y.z.zip`** from the
   [Releases page](https://github.com/pavstev/Glasnik/releases/latest) and unzip it.
2. Move `Glasnik.app` to `/Applications`.
3. It's **ad‑hoc signed** (no paid Apple Developer account), so on first launch Gatekeeper
   will balk. Either **right‑click → Open → Open**, or run once:
   `xattr -dr com.apple.quarantine /Applications/Glasnik.app`
4. Look for the **Г** in the menu bar (no Dock icon).

On first launch Glasnik downloads the `openai_whisper-large-v3` model (~2.9 GB) from
Hugging Face — the popover shows **"Preparing model…"** until it's ready (the model is
prewarmed at launch so the first transcription is fast), and macOS prompts once for the
microphone.

### Optional: polished translations with Ollama

```sh
brew install ollama        # or download from https://ollama.com
ollama pull qwen2.5:3b
ollama serve               # leave running
```

When Ollama is running, `qwen2.5:3b` produces cleaner English and honors your tone +
glossary. Without it, Glasnik falls back to Whisper's own translation.

## Updating

Glasnik checks GitHub Releases on launch (and via the **↻** button) and shows an
"Update available" banner linking to the new release. To upgrade, click the banner, or
just **re‑run the installer** — it always fetches the latest release and replaces the
installed app in place:

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/Glasnik/main/scripts/install.sh | bash
```

## How it works

```
record (16 kHz mono WAV)
   └─ WhisperKit (large-v3, VAD chunking)  ──▶  Serbian transcript   (task: transcribe, language: sr)
        └─ translate:
             ├─ Ollama qwen2.5:3b  ──▶  polished English   (preferred, honors tone + glossary)
             └─ WhisperKit          ──▶  English baseline   (offline fallback, task: translate)
   └─ show Serbian + English, auto‑copy English, save to history
```

- Single app‑level state machine: `preparing → idle → recording → transcribing → translating → done` (+ `error`).
- A no‑speech guard prevents Whisper from "hallucinating" text out of silence.
- The global hotkey uses Carbon's `RegisterEventHotKey` directly — no third‑party dependency.

## Usage

- **Click** the menu bar **Г** to open the popover; the **Record / History** toggle switches views.
- **`⌥⇧Space`** from any app starts/stops recording and opens the popover.
- The menu bar glyph turns into a **red live waveform** while recording.
- On completion the English shows, **auto‑copies**, and is saved to history. **Copy English** re‑copies; the **↻** footer button checks for updates.
- Set the **tone** and **glossary** in Settings (⌘,).

## Build from source

You do **not** need full Xcode — Glasnik builds with the Command Line Tools via SwiftPM.

```sh
xcode-select --install     # if you don't already have the CLT
git clone https://github.com/pavstev/Glasnik.git
cd Glasnik
./bundle.sh                # swift build + assemble & ad-hoc sign Glasnik.app
open Glasnik.app
```

`bundle.sh` env overrides: `GLASNIK_VERSION=1.2.3` stamps a version; `GLASNIK_UNIVERSAL=1`
builds a universal (arm64 + x86_64) binary. The icon is generated by
`swift scripts/make-icon.swift` + `iconutil`. Tests run with `swift test` (the CLT bundles
no test framework, so they run in CI on the Xcode‑based runner).

## Releasing (maintainer)

Releases are **fully automated** by GitHub Actions
([`release.yml`](.github/workflows/release.yml)):

```sh
git tag v1.2.0 && git push origin v1.2.0
```

The workflow builds on a macOS runner, runs `bundle.sh` (stamping the tag version),
zips the app with `ditto`, and publishes a GitHub Release with auto‑generated notes.
Every push/PR to `main` is build‑checked + tested by [`ci.yml`](.github/workflows/ci.yml).

## Project layout

| File | Responsibility |
| --- | --- |
| `Package.swift` | SwiftPM build (CLT, no Xcode) + test target |
| `bundle.sh` | Builds + assembles & ad‑hoc signs `Glasnik.app` |
| `AGENTS.md` | Setup instructions an AI agent follows to install the app |
| `scripts/install.sh` | One‑line installer (cleanup → latest release → launch) |
| `scripts/cleanup.sh` | Clean‑slate precondition (uninstall; `--purge` for history/model) |
| `scripts/make-icon.swift` | Generates the ГG `Glasnik.icns` |
| `project.yml` | Optional XcodeGen spec |
| `.github/workflows/` | CI (build + test) and tag‑triggered release |
| `Sources/GlasnikApp.swift` | `@main`; app delegate adaptor + Settings scene |
| `Sources/AppDelegate.swift` | Status item, popover, hotkey, menu‑bar glyph + waveform |
| `Sources/RecorderViewModel.swift` | `@Observable @MainActor` — recording/translation logic |
| `Sources/WhisperEngine.swift` | WhisperKit wrapper (transcribe + translate, VAD, prewarm) |
| `Sources/OllamaClient.swift` | Ollama `/api/generate` client + tone/glossary prompt |
| `Sources/HistoryStore.swift` | JSON‑backed translation history |
| `Sources/HistoryView.swift` | Searchable history UI |
| `Sources/TranslationPreferences.swift` | Tone + glossary (UserDefaults) |
| `Sources/PopoverView.swift` | SwiftUI popover (record, result, history) |
| `Sources/UpdateChecker.swift` | GitHub Releases update check |
| `Sources/GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper (⌥⇧Space) |
| `Sources/Log.swift` | os.Logger categories |

## Notes & limitations

- First run downloads `large-v3` (~2.9 GB); cached thereafter.
- Releases are ad‑hoc signed (not notarized) — see the Gatekeeper step in **Install**.
- The offline Whisper translation (no Ollama) is rougher than Ollama's polish.
- Released binaries are arm64; set `GLASNIK_UNIVERSAL=1` to build universal.
- Bundle id: `com.stevanpavlovic.Glasnik`.

## Dependencies

- [argmax-oss-swift / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — on‑device speech (pinned to 1.0.0)
- [Ollama](https://ollama.com) + `qwen2.5:3b` — optional translation polish

## License

[MIT](LICENSE) © Stevan Pavlović
