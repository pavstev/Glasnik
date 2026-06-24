<p align="center">
  <img src="docs/icon.png" width="120" alt="Šapat icon — Ш monogram">
</p>

<h1 align="center">Šapat</h1>

<p align="center">A native macOS menu bar app that turns Serbian speech into clean, precise English — on-device.</p>

<p align="center">
  <a href="https://github.com/pavstev/Sapat/actions/workflows/ci.yml"><img src="https://github.com/pavstev/Sapat/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/pavstev/Sapat/releases/latest"><img src="https://img.shields.io/github/v/release/pavstev/Sapat?sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/pavstev/Sapat" alt="MIT"></a>
</p>

---

Press `⌥⇧Space` (or click the menu bar **Ш**), speak Serbian, and Šapat transcribes it
on-device with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), refines it into
concise English with a local [LM Studio](https://lmstudio.ai) model, and copies the result
to your clipboard. Everything runs on your Mac.

> *Šapat* (шапат) is Serbian for "whisper" — a nod to the on-device Whisper engine. The
> icon is **Ш**, the Cyrillic letter that opens the word.

## How it works

```
record (16 kHz mono WAV)
   └─ WhisperKit large-v3 (Serbian, VAD)  ──▶  transcript          quiet pauses are skipped,
        └─ refine:                                                  long monologues stay accurate
             ├─ LM Studio · Qwen3-8B (MLX)  ──▶  clean English      preferred: dedup + formalize
             └─ WhisperKit translate        ──▶  English baseline   offline fallback
   └─ show both, auto-copy English, save to history
```

The refiner is told to **work only with what was said**: it removes repetition and filler,
states your intent **once** in precise technical English, and **adds nothing** — no invented
facts. It returns the clean text only (no LM preambles, quotes, or notes; a sanitizer strips
any that leak). Tone presets and a glossary tune the result.

## Features

- **On-device transcription** — WhisperKit `large-v3` with VAD silence handling, tuned for long, pause-heavy monologues (5–10 min).
- **Local refinement** — LM Studio (`qwen/qwen3-8b`, MLX) deduplicates and formalizes into concise English without fabricating; output-only.
- **Offline fallback** — Whisper's own translate task when LM Studio isn't running.
- **Tone & glossary**, plus a configurable model id (Settings).
- **Concise history** — searchable, with tap-to-expand rows.
- **Global hotkey** `⌥⇧Space` to start/stop; **Esc** cancels a recording. The menu bar **Ш** animates as a live waveform while recording, with a live timer and first-run model-download progress in the popover.
- **Automatic updates** — checks GitHub Releases, then downloads, checksum-verifies, swaps the bundle in place, and relaunches.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/Sapat/main/scripts/install.sh | bash
```

Cleans up any prior install, downloads the latest release, strips the Gatekeeper quarantine
(it's **ad-hoc signed**, so a manual install needs `xattr -dr com.apple.quarantine
/Applications/Sapat.app`), installs to `/Applications`, and launches. First launch downloads
the `large-v3` model (~2.9 GB) and asks once for the microphone. Reset with
`./scripts/cleanup.sh [--purge]`.

### Local refinement with LM Studio

```sh
brew install --cask lm-studio        # or download from https://lmstudio.ai
lms get qwen3-8b --mlx               # MLX build, strong Serbian + instruction-following
lms server start                     # OpenAI-compatible API on :1234
```

Without LM Studio, Šapat falls back to Whisper's offline translation. The model id is set in
Settings (default `qwen/qwen3-8b`). Any OpenAI-compatible local server works — e.g. Ollama on
`:11434/v1` — just point the endpoint/model at it.

## Build from source

No full Xcode needed — Šapat builds with the Command Line Tools via SwiftPM.

```sh
xcode-select --install
git clone https://github.com/pavstev/Sapat.git && cd Sapat
./bundle.sh && open Sapat.app        # swift build + assemble & ad-hoc sign
```

Overrides: `SAPAT_VERSION=1.2.3` stamps a version; `SAPAT_UNIVERSAL=1` builds universal.
Tests: `swift test`.

## Releasing

Tag-triggered and automated by [`release.yml`](.github/workflows/release.yml): `git tag
v1.3.0 && git push origin v1.3.0` builds, zips, and publishes a GitHub Release the in-app
updater picks up. Every push/PR to `main` is build-checked + tested by
[`ci.yml`](.github/workflows/ci.yml).

## Project layout

| Path | Responsibility |
| --- | --- |
| `Sources/Brand.swift` | Single source of truth: name, bundle id, repo slug, paths |
| `Sources/SapatApp.swift` · `AppDelegate.swift` | `@main`; status item, popover, hotkey, menu-bar glyph/waveform |
| `Sources/RecorderViewModel.swift` | `@Observable @MainActor` record → transcribe → refine flow |
| `Sources/WhisperEngine.swift` | WhisperKit wrapper, tuned for long-form VAD silence handling |
| `Sources/LMStudioClient.swift` | OpenAI-compatible refiner client + the refinement system prompt |
| `Sources/OutputSanitizer.swift` | Conservative scaffolding stripper (never eats real content) |
| `Sources/HistoryStore.swift` · `HistoryView.swift` | JSON history + concise collapsible UI |
| `Sources/PopoverView.swift` · `Theme.swift` | SwiftUI popover + copper-on-stone design tokens |
| `Sources/UpdateChecker.swift` | GitHub Releases auto-updater (download → verify → swap) |
| `Sources/GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper (⌥⇧Space) |
| `bundle.sh` · `scripts/` · `.github/workflows/` | Build/assemble, install/cleanup, CI + release |

## Notes

- First run downloads `large-v3` (~2.9 GB); cached thereafter. Releases are ad-hoc signed, not notarized.
- The offline Whisper translation is rougher than the LM Studio refinement.
- Bundle id: `com.stevanpavlovic.Sapat`.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — on-device speech (pinned to 1.0.0)
- [LM Studio](https://lmstudio.ai) + an MLX model (`qwen/qwen3-8b`) — optional local refinement

## License

[MIT](LICENSE) © Stevan Pavlović
