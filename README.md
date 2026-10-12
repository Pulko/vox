# Vox

Push-to-talk, on-device text transformer for macOS. Hold **Option-Space**, speak an instruction about the selected text, and Vox pastes the result back into the focused app.

## Requirements

- macOS 14+, Apple Silicon
- Xcode 15+ (MLX Metal shaders must be compiled by Xcode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```sh
xcodegen generate
xcodebuild -scheme Vox -configuration Release -destination 'platform=macOS' build
```

Or open `Vox.xcodeproj` in Xcode and run. The first launch downloads Llama-3.2-3B-Instruct-4bit (~1.8 GB) and whisper-base (~200 MB) into `~/Library/Application Support/Vox/models/`.

Grant **Accessibility** and **Microphone** when prompted. Rebuilds that change the code signature need Accessibility re-approved.

Quit from the status item, or `killall Vox`.
