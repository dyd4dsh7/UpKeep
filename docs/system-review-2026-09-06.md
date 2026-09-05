# System review — 6 September 2026

This review covered application/source scanning, update execution and reservations,
Homebrew and developer packages, local models, backup/history handling, publisher
HTTP/cache behavior, release parsers, update selection, and local packaging/startup.
The working tree was clean at the start. Changes are local; nothing was committed,
pushed, published, or installed over `/Applications/Upkeep.app`.

## Confirmed issues fixed

| # | Issue and trigger | Fix | Regression evidence |
|---|---|---|---|
| 1 | A scan requested during another scan returned immediately; an update could finish without a fresh post-install inventory. | Queue a follow-up scan and wait for it before completing callers. | `concurrentScanRequestsWaitForAFreshFollowup` |
| 2 | Refreshing a developer package overwrote the version menu for a different selected package. | Only update selection state for the selected package. | `refreshingAnotherPackageDoesNotReplaceSelectedVersions` |
| 3 | Older version requests could finish after newer requests and overwrite their menu/cache results. | Track request identity for selection and per-key cache writes. | `supersededVersionRequestCannotOverwriteNewerResults` |
| 4 | Cancelling a version request left its loading indicator active. | Clear loading state when the owning request exits, including cancellation. | `cancelledVersionRequestClearsLoadingState` |
| 5 | Homebrew batch backup failure could disappear during the rescan and be reported as success. | Preserve the backup error through refresh and batch reporting. | `homebrewBatchPreservesBackupFailureAcrossRescan` |
| 6 | The same LM Studio model in configured and legacy storage produced duplicate IDs; model refresh dictionaries could trap. | Prefer configured storage and safely deduplicate both targeted and full model results. | `duplicateModelInventoryDoesNotCrashTargetedRefresh`; source review of discovery/full merge |
| 7 | Empty Homebrew catalog versions indexed an empty array. | Reject missing version components. | `emptyHomebrewCatalogVersionCannotCrashScan` |
| 8 | Oversized/nonfinite model byte counts could trap during `Int64` conversion. | Check finite, nonnegative, representable bounds. | `modelByteCountsRejectUnrepresentableValues` |
| 9 | Oversized cleanup estimates could trap during `Int64` conversion. | Validate bounds before conversion. | `cleanupEstimateRejectsOverflowingByteCounts` |
| 10 | Publisher cache keys collided after punctuation replacement or 180-character truncation. | Hash the complete key for the cache filename. | `publisherCacheKeysDoNotCollideAfterSanitizationOrTruncation` |
| 11 | Publisher and Homebrew catalog failures silently returned indefinitely expired cache contents, appearing successful/current. | Propagate failures after cache expiry; retain normal fresh-cache lifetimes and existing scanner failure handling. | `expiredPublisherCacheDoesNotHideFetchFailures`; Homebrew source review |
| 12 | Malformed Sparkle XML after a valid item was treated as a successful check with no update. | Invalidate the parsed-items flag when XML parsing fails. | `malformedFeedAfterValidEntryIsNotACompleteCheck` |
| 13 | Sparkle delta enclosures overwrote the full-download URL/signature metadata. | Ignore nested delta entries when selecting full installers. | `sparkleDeltaEnclosuresDoNotReplaceFullDownloadMetadata` |
| 14 | A publisher-declared beta with a numeric version could be selected as a recommended stable update. | Include publisher channel metadata in risk classification; model channels also retain prerelease classification. | `publisherDeclaredPrereleasesAreNeverRecommendedByDefault` |
| 15 | Homebrew receipts could lag behind a self-updated app and offer a downgrade. The running UI showed CodexBar 0.56.3 → 0.56.2. | Reconcile casks with the actual installed app version and suppress older catalog targets during full/targeted refresh. | `newerInstalledAppSuppressesStaleHomebrewDowngrade`; local UI check |

## Verification

- **229 tests passed**, including 15 added regression tests; warnings-as-errors enabled.
- Final local package build and `--verify` startup check exited successfully. `codesign --verify --deep --strict dist/Upkeep.app` passed for the ad-hoc debug signature. This is not a notarized release.
- Inspected the running Updates and Developer workspaces. CodexBar now shows 0.56.3 → 0.56.6 from its publisher, with the stale 0.56.2 Homebrew offer removed.
- The live scan reported one VS Code Marketplace extension-check failure and displayed the source warning. That external failure remains visible; full third-party availability is not claimed.
- Desktop UI was inspected. A window-resize attempt did not change the captured dimensions, so narrow-window validation is not claimed.
- Verification logs are in `outputs/system-review-2026-09-06/tests.log` and `outputs/system-review-2026-09-06/build-launch.log` (ignored local artifacts).

- Test command: `swift test --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -Xswiftc -warnings-as-errors`.
- Local package/startup command: `UPKEEP_SDK=macosx26.5 ./script/build_and_run.sh --verify`.
- The default macOS 27 beta SDK lacked the `SwiftUIMacros.StateMacro` plugin. The installed 26.5 SDK builds this code successfully; no system SDK/toolchain settings were changed.
- Compiler-cache sandbox restrictions were resolved by running authorized build/test commands with normal cache access.
- Test updates, backups, restores and package mutations use fixtures. No real application/package/model update, cleanup, restore or macOS installation was performed as part of testing.
- This is a system-wide bug review, not a guarantee that every possible defect has been eliminated. Live third-party installers, authenticated updates, notarization and macOS 14 execution remain outside the verified coverage.
