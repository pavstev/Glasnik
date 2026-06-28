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
        └─ refine with LM Studio · Qwen3-8B (MLX):                  long monologues stay accurate
             ├─ fits the model's context  ──▶  one pass            dedup + formalize
             └─ too long for context      ──▶  split → refine →     every part is refined, then
                                                merge               merged so nothing is dropped
   └─ show both, auto-copy English, save to history
```

The refiner is told to **work only with what was said**: it removes repetition and filler,
states your intent **once** in precise technical English, and **adds nothing** — no invented
facts. It returns the clean text only (no LM preambles, quotes, or notes; a sanitizer strips
any that leak). Tone presets and a glossary tune the result.

## Features

- **On-device transcription** — WhisperKit `large-v3` with VAD silence handling, tuned for long, pause-heavy monologues (5–10 min).
- **Local refinement** — LM Studio (`qwen/qwen3-8b`, MLX) deduplicates and formalizes into concise English without fabricating; output-only.
- **Whole-recording guarantee** — long transcripts that exceed the model's context are split on sentence boundaries, refined piece by piece, then merged + de-duped, so the **beginning is never silently dropped**.
- **Auto-managed LM Studio** — on launch Šapat starts LM Studio's server and downloads + loads the model itself; if it can't, the transcript stays on screen with a clear Retry.
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

### Local refinement with LM Studio (required)

```sh
brew install --cask lm-studio        # or download from https://lmstudio.ai
#  then, once, in LM Studio: install the `lms` command-line tool
```

LM Studio does the refinement, so it's required. You don't have to configure it: on launch
Šapat finds the `lms` CLI, starts the server (`:1234`), and downloads + loads the model
(`qwen/qwen3-8b` MLX, ~5 GB) with a generous context window. If LM Studio can't be made ready,
Šapat keeps your transcript on screen and offers **Retry** + **Open LM Studio** rather than
producing a rougher result. The model id is configurable in Settings.

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
| `Sources/LMStudioClient.swift` | LM Studio refiner client: context query, chunk-if-needed + merge, system prompt |
| `Sources/LMStudioManager.swift` | Auto-start via the `lms` CLI: server up, model downloaded + loaded |
| `Sources/TranscriptChunker.swift` | Pure, tested sentence-boundary splitter for long transcripts |
| `Sources/OutputSanitizer.swift` | Conservative scaffolding stripper (never eats real content) |
| `Sources/HistoryStore.swift` · `HistoryView.swift` | JSON history + concise collapsible UI |
| `Sources/PopoverView.swift` · `Theme.swift` | SwiftUI popover + copper-on-stone design tokens |
| `Sources/UpdateChecker.swift` | GitHub Releases auto-updater (download → verify → swap) |
| `Sources/GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper (⌥⇧Space) |
| `bundle.sh` · `scripts/` · `.github/workflows/` | Build/assemble, install/cleanup, CI + release |

## Notes

- First run downloads `large-v3` (~2.9 GB) and, via LM Studio, the refinement model (~5 GB); both cached thereafter. Releases are ad-hoc signed, not notarized.
- LM Studio is required for refinement; Šapat starts its server and loads the model automatically (and chunks long transcripts so none is dropped).
- Bundle id: `com.stevanpavlovic.Sapat`.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — on-device speech (pinned to 1.0.0)
- [LM Studio](https://lmstudio.ai) + its `lms` CLI and an MLX model (`qwen/qwen3-8b`) — required for refinement (auto-managed)

## License

[MIT](LICENSE) © Stevan Pavlović
