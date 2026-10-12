# Vox

A menu-bar macOS agent: hold **Option-Space**, speak what to do with the **highlighted** text, and get finished text back on the clipboard (and Cmd-V when Accessibility allows).

Everything after you choose a model runs on-device.

## How it works

Vox is a background extra (`LSUIElement`). It does not appear in the Dock or Cmd-Tab.

1. **Key down.** It reads the current Accessibility selection (`AXSelectedText`) and starts the microphone. If nothing is highlighted, context is empty — it never copies the clipboard.
2. **Key up.** Recording stops. WhisperKit (whisper-base) transcribes on the Neural Engine.
3. **Clean.** `NaturalLanguage` (`NLTagger` lexical class) drops interjections and consecutive duplicate words. No filler-word list.
4. **Parse (optional).** If an instruction parser is installed **and** in use, a small MLX model turns the cleaned speech into JSON. If the parser is missing, failed, or returns junk, this step is skipped.
5. **Write.** The text-writer model turns the selection plus cleaned speech (and parse JSON when present) into paste-ready text.
6. **Deliver.** Clipboard, plus Cmd-V when Accessibility allows.

## Menu bar

- **Models…** — two lists:
  - **Text writer:** Llama 3.2 3B (1.8 GB), Qwen 2.5 3B (1.8 GB), Phi 3.5 Mini (2.2 GB), or None.
  - **Instruction parser (optional):** Qwen3 0.6B (0.4 GB), Gemma 3 1B (0.8 GB), Llama 3.2 1B (0.7 GB), Qwen3 1.7B (1.0 GB), or None.  
  **Use** downloads if needed. **Remove** deletes that folder. Nothing auto-downloads. A parser that is not installed is ignored; speech still goes through NaturalLanguage into the writer.
- **Sounds** — Start and Done each have Mute plus system sounds. The icon is slashed only when both are muted.
- **Edit System Prompt…** — override the writer system prompt.
- Accessibility helpers and Quit.

Weights live in `~/Library/Application Support/Vox/models/` (`llm/<folder>/` and `openai_whisper-base`). Whisper (~200 MB) downloads with the first model you Use. Grant **Microphone** and **Accessibility** when asked. Ad-hoc rebuilds are a new identity: toggle Vox off/on in Accessibility if auto-paste stops.

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
