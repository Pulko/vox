# Vox

A background macOS agent: hold **Option-Space**, speak what to do with the selected text, and get finished text back — on the clipboard, and pasted into the focused app when Accessibility allows.

Everything runs on-device. No network after the first model download.

## How it works

Vox lives in the menu bar (`LSUIElement`). It does not appear in the Dock or Cmd-Tab.

1. **Key down.** It snapshots the current selection (Accessibility selected-text, or a brief Cmd-C fallback) and starts recording the microphone.
2. **Key up.** Recording stops. WhisperKit transcribes the clip on the Neural Engine.
3. **Generate.** Llama 3.2 3B Instruct (4-bit, MLX) treats the transcript as a command and the selection as source data. It may reply, rewrite, reformat, or compose — whatever the spoken request implies. The model is prompted to output only the finished text, grounded in those two inputs.
4. **Deliver.** The result is written to the clipboard. If this binary is trusted for Accessibility, Vox also synthesizes Cmd-V so it lands in the focused field. If paste does not stick (browsers that steal focus, untrusted Accessibility), Cmd-V still works from the clipboard.

First launch downloads weights into `~/Library/Application Support/Vox/models/` (selected LLM under `llm/`, whisper-base ~200 MB) and asks for **Microphone** and **Accessibility**. The menu bar extra can switch among curated 1–3B MLX models (downloads on demand) and mute or pick start/done sounds; mute draws a slash on the icon. Ad-hoc rebuilds are a new identity: toggle Vox off/on in Accessibility if auto-paste stops.

Quit from the menu bar extra, or `killall Vox`.

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
