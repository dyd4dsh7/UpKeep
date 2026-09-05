# Cleanup UI/UX refinement

- A consistent Cleanup toolbar button now opens a focused review sheet for Homebrew or supported developer managers.
- Manager selection, removal scope, read-only checking, estimates, cleanup progress, errors, and completion remain in one context.
- Cache footprint is explicitly distinguished from recoverable space. Zero measured recovery no longer claims no files were removed.
- Check and Clean Up are separate actions; the destructive action retains an explicit confirmation with Cancel.
- Switching manager discards the old estimate. Busy operations prevent competing actions and dismissal.
- Errors are delivered to the sheet with retry instead of presenting a competing global alert. Existing callers retain their global error behavior.
- Technical command and executable details are available through a disclosure rather than dominating confirmation or result banners.

Uses native sheets and confirmation dialogs following Apple's [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets), and [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) guidance.

Validation: 232 tests passed using SDK 26.5, including new injected cleanup-error coverage. Built and launched locally. Visually checked the dark-mode developer cleanup sheet, read-only npm cache check (1.03 GB shown as cache footprint), destructive confirmation/cancellation, and switching to pnpm resetting the estimate. No actual cleanup command was executed during UI QA. Real deletion success, light appearance, and VoiceOver navigation were not exercised. Existing macOS 27 beta SDK tooling limitation remains; verification uses SDK 26.5.
