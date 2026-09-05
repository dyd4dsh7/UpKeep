# macOS design refinement — 6 September 2026

Reviewed Apple's current [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), and [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) guidance. The implementation uses standard SwiftUI navigation, toolbars, inspectors, grouped controls, and semantic colors. Liquid Glass remains in system navigation and controls; content does not need a custom glass layer.

## Changes

1. Replaced hand-drawn sidebar count capsules with native badges.
2. Made the inspector width adjustable from 320 to 500 points, with a 380-point default.
3. Standardized list names on body-weight typography, removing oversized comfortable-row titles.
4. Removed comfortable-row icon enlargement while retaining the compact density option.
5. Reduced custom toolbar symbol sizing and fixed frames so standard controls govern their layout.
6. Replaced the shared update card's custom fill and outline with a native GroupBox.
7. Applied that shared grouped treatment to developer, Homebrew, and model metadata, and reduced unnecessarily wide grid gutters.
8. Reduced package and model inspector title sizes and normalized section headings across application/security details.
9. Simplified the update decision header by removing duplicate colored metric cards, keeping one review action, and clarifying that review counts span all sources.
10. Removed the review button's global default Return binding so it does not compete with other focused controls.
11. Put developer version installation on a separate row from the version picker and refresh control.
12. Replaced custom appearance selection cards with native segmented pickers in Settings and removed their unused hover/selection drawing code.
13. Used a semantic warning surface and more readable callout text in source-problem details.

The previous theme-aware, padded Dock icon fix is retained without alteration in this design pass.

## Verification

- Final local package build and launch verification succeeded using macOS SDK 26.5.
- All 231 tests passed, including the Dock appearance and transparent-margin regression tests.
- `git diff --check` passed.
- Visually inspected native dark-mode Updates, Developer/Bun, Homebrew, AI Models, Settings, and Applications/TablePro inspector screens. Main actions, metadata, selected rows, source sections, and Settings segments were visible.
- No app/package updates were installed during design QA.

## Limits

The installed default macOS 27 beta SDK has a missing SwiftUI macro plugin, so the verified build uses the working 26.5 SDK. This is not a claim of latest-beta SDK build compatibility. Full light-mode, reduced-transparency, increased-contrast, minimum-window-size, and VoiceOver interaction sweeps remain unverified. Existing native controls provide their platform behavior, but that is not a substitute for those checks. No release was published, and `/Applications/Upkeep.app` was not replaced; the launched local build is `dist/Upkeep.app`.
