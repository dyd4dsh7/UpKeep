# Upkeep

Upkeep is a native SwiftUI macOS application that scans installed apps and checks trusted update sources.

The app includes a standard unified macOS toolbar with a prominent live update counter, a menu-bar status item, and a Dock icon badge using the same filtered count. It also provides native Settings for every source and supported developer manager, configurable launch/background checks, beta visibility, and notifications.

Individual app, package, and local-model releases can be skipped without hiding later versions, or ignored until restored from Settings. Skipped and ignored updates are excluded from the update list, sidebar badge, menu-bar count, and notifications.

## Update sources

- Mac App Store metadata for apps with App Store receipts
- Sparkle appcast feeds declared by applications
- Homebrew casks, when Homebrew is installed
- GitHub Releases discovered from app and Electron update metadata
- Ollama registry manifests and LM Studio model repositories for locally installed AI models

## Homebrew workspace

Upkeep inventories installed formulae and casks, separates requested packages from dependencies, filters available updates, and exposes package details. Apps matched against Homebrew's official cask catalog can be adopted with Homebrew's native `--adopt` workflow.

## macOS and recovery

The macOS section reads Apple's Software Update catalog, lists compatible full installers, and opens Apple's authenticated settings for stable or beta-channel enrollment and installation. Before supported GUI app updates, Upkeep creates a local backup and adds a History entry that can restore the previous app bundle. Formula and macOS recovery entries explain the supported Time Machine, versioned-formula, or macOS Recovery path when direct rollback is not available.

## Developer packages

Upkeep inventories globally installed npm, pnpm, Python/pip, RubyGems, and Cargo packages when their package managers are available. Manager filters only appear for installed tools, and packages without updates remain visible with a Current status. It preserves the discovered executable path—such as an NVM Node installation—when applying an update. Apps not currently managed by Homebrew also contribute to the update count when Homebrew's official cask catalog has a newer version; Upkeep backs up the app before replacing it and enrolling it under Homebrew management.

Package rows use bundled manager artwork and open detailed metadata when selected. npm, pnpm, pip, RubyGems, and Cargo packages can be installed at an explicit published version. Homebrew version selection follows its versioned-formula model; historical cask releases are only available when the cask itself exposes them.

Developer package details load available releases from the package manager or registry into a version menu and select the latest release by default. The Developer toolbar can refresh all installed managers or only npm, pnpm, Python, RubyGems, or Cargo.

## Local AI models

Upkeep detects locally installed Ollama and LM Studio models without showing empty runtime sections. Ollama models are checked by comparing their local and registry manifest digests. LM Studio model files are checked against their originating Hugging Face repository. Supported updates run through `ollama pull` or `lms get`, so credentials, storage, and model management remain with the installed runtime.

The model workspace uses bundled artwork downloaded from the official Ollama and LM Studio websites, with a native generic AI symbol when a logo is unavailable.

## Changelog

Upkeep includes its native changelog inside Settings. The complete release history is also maintained in [CHANGELOG.md](CHANGELOG.md).

Upkeep never downloads executables from its own servers. App Store updates open in the App Store, Sparkle downloads come from the app's declared developer feed, and Homebrew apps are upgraded through the local Homebrew installation.

## Build

Requires macOS 14 or newer and Apple Command Line Tools.

```sh
swift test
./scripts/package-app.sh
open outputs/Upkeep.zip
```
