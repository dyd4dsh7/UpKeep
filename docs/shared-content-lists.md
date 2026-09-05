# Shared content lists

Updates, Applications, Adoptable, Homebrew, Developer, AI Models, macOS, History, and Search now use `upkeepContentList()` with `StandardItemRow`. The sidebar keeps the distinct native navigation style.

The shared design owns inset list chrome, density-aware minimum row height, separators, native selection, row typography and spacing, and the standard primary-action style. Removed the custom hover background to avoid an apparent second selection. AI model, macOS, history, and search actions now use the same capsule button style and minimum action width as app/package updates. Long action labels may grow to remain readable. macOS uses the shared installed-version presentation. Lists retain their existing actions and selection semantics.

Validation: SDK 26.5 build; 232 tests passed before the final macOS button-only style correction, which was included in the final build. No update or cleanup actions were executed during UI checks.
