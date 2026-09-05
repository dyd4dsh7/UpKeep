# Shared information panel

Applications, Homebrew packages, developer packages, and local models use `InfoPanel` and `InfoPanelHeader` in `Sources/Upkeep/Views/InfoPanel.swift`.

The shared components own the fixed header, 44-point icon slot, title typography, 20-point content padding/spacing, divider, scrolling body, and Close/Escape behavior. Item-specific views supply content and preserve their existing operations and Basic/Advanced visibility rules. Dependencies use a disclosure, consistent with version and security details.

Validation: SDK 26.5 build and 232 tests passed. The installed app is a local debug package, not a published release.
