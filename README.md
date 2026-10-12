# Vox

A menu-bar macOS agent: hold **Option-Space**, speak what to do with the **highlighted** text, and get finished text back on the clipboard (and Cmd-V when Accessibility allows).

Everything after you choose a model runs on-device.

## How it works

Vox is a background extra (`LSUIElement`). It does not appear in the Dock or Cmd-Tab.

1. **Key down.** It reads the current Accessibility selection (`AXSelectedText`) and starts the microphone. If nothing is highlighted, context is empty — it never copies the clipboard.
2. **Key up.** Recording stops. WhisperKit (whisper-base) transcribes on the Neural Engine.
3. **Generate.** The selected MLX instruct model treats the transcript as a command and the selection as source data. It may reply, rewrite, reformat, or compose. Output is finished text only.
4. **Deliver.** The result is written to the clipboard. If this binary is trusted for Accessibility, Vox also posts Cmd-V. If auto-paste misses (webviews, untrusted Accessibility), paste from the clipboard yourself.

## Menu bar

- **Language model** — **None** (default; nothing downloads) or a curated 4-bit MLX model with size:
  - Llama 3.2 3B — 1.8 GB
  - Llama 3.2 1B — 0.7 GB
  - Qwen 2.5 3B — 1.8 GB
  - Qwen 2.5 1.5B — 0.9 GB
  - Phi 3.5 Mini — 2.2 GB  
  A checkmark means installed and loaded. Uninstalled rows say `not installed`. **Remove from This Mac** deletes that LLM folder only (not Whisper).
- **Sounds** — mute (slash on the icon) or pick start/done system sounds.
- **Edit System Prompt…** — override the compiled-in prompt; Save applies on the next run; Reset restores the default.
- Accessibility helpers and Quit.

Weights live in `~/Library/Application Support/Vox/models/` (`llm/<folder>/` and `openai_whisper-base`). Whisper (~200 MB) downloads with the first LLM you select. Grant **Microphone** and **Accessibility** when asked. Ad-hoc rebuilds are a new identity: toggle Vox off/on in Accessibility if auto-paste stops.

Quit from the menu extra, or `killall Vox`.

## Requirements

- macOS 14+, Apple Silicon
- Xcode 15+ (MLX Metal shaders must be compiled by Xcode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```sh
xcodegen generate
xcodebuild -scheme Vox -configuration Release -destination 'platform=macOS' build
```

Or open `Vox.xcodeproj` in Xcode and run.
