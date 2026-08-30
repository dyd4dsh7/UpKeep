# Upkeep log review — 31 August 2026

## Coverage

Reviewed all 2,000 retained application diagnostics (23–30 August UTC), the
24-hour macOS unified log for Upkeep, both available Upkeep crash reports
(09:57 and 09:59 NZST), and the saved review/build/test logs in `outputs`.
Older application entries have rolled out of the retention window; this is not
a claim about every log ever produced or every installed app on the Mac.

## Findings and changes

- **pnpm cleanup preview failed with EROFS.** Reproduced through Developer →
  Cleanup → Check pnpm Store. The prior TMPDIR fix was insufficient: pnpm probes
  its current working directory, which is `/` for the launched app. Global
  developer commands now use a writable home directory, with a temporary-directory
  fallback. A regression test exercises the relative-file probe. The rebuilt app
  successfully measured the store at 23.22 GB in 14.2 seconds. The confirmation
  was cancelled; no cleanup or package installation was performed.
- **Native progress views generated invalid-size faults.** The prior 24-hour log
  contained 982 progress-view configuration faults. Scaling surface transitions
  passed fractional sizes to AppKit progress controls. Surface transitions now
  fade without scaling. Fresh launches, scans, and narrow-window navigation were
  checked for new geometry, constraint, and progress-view faults.
- **Tests polluted real diagnostics.** Simulated review/history failures had
  been written into the user's log. The shared store now persists only inside
  the packaged Upkeep app; test runners and standalone review harnesses use
  memory. Explicit file-backed diagnostic tests remain supported. A regression
  test confirms that recording, exporting, and clearing an in-memory store never
  reads or overwrites an existing file. Historical entries were not deleted.
- **An app with a failed publisher check could say “Up to date.”** Reproduced
  by opening ProtonVPN from search while its Sparkle check was blocked. Per-app
  failed sources now survive full and individual refreshes, and the inspector
  shows “Update check incomplete” with an explanation. Tests cover failure,
  successful retry, isolation from other apps, and full-scan reset.
- **Blocked-address diagnostics were imprecise.** The error now includes reserved
  addresses and suggests checking DNS/VPN/network filters. Sparkle failure entries
  include the publisher hostname without recording URL credentials or query data.
- **Selecting a search result published state during a view update.** A fresh
  process reproduced the SwiftUI fault at 10:36:37 NZST when selecting ProtonVPN
  from global search. The list's selection was a published property on a private
  observable object. It now uses view-local `@State`, avoiding synchronous
  object-change notifications while AppKit reconciles list selection. The same
  interaction in the rebuilt app opened the correct inspector without a fault,
  at both desktop width and the narrow half-screen window.

## Existing or external conditions

- Both saved crashes were AppKit constraint-loop aborts. The existing split-view
  fix predates this review. The current app was exercised at desktop width and
  in a narrow half-screen window, including inspector and search navigation.
- `protonvpn.com` resolved to `203.0.113.250` during this review. That reserved
  address is correctly rejected by the publisher safety policy. No DNS settings,
  network filters, publisher URLs, or safety checks were bypassed or changed.
  Resolving the underlying network condition requires the network owner to
  determine why that address is being returned.
- The historical single VS Code marketplace warning did not recur in fresh
  full scans. All detected developer managers completed successfully.
- macOS App Intents service-connection and BaseBoard task-port errors remain in
  the unified log. These originate in system frameworks; this review did not
  establish an Upkeep source-code remedy or change system services.

## Delivery boundary

The final `swift test` run passed all 207 tests, including the new regressions.
`git diff --check` passed. The debug packaging and process-launch check succeeded.

At the end of local verification, changes were uncommitted. The debug app was
rebuilt and launched from `dist/Upkeep.app`; `outputs/Upkeep.zip` is a local debug
package, not a notarized release. No release publication, package update, or
destructive cleanup was performed. Subsequent Git publication is separate from
these local validation results.
Ignored evidence is kept in `outputs/log-review-2026-08-31/`.

## Final verification follow-up

The earlier changes were committed as `1be4776` during the follow-up review.
At completion of local verification, the additional `GlobalSearchView.swift` fix
and this report update were uncommitted. Subsequent Git publication is separate
from these checks; no release was published during verification.

The rebuilt process (PID 81655) completed a full scan and the reproduced search
interaction. Its checked unified log contained no faults, including no SwiftUI
publication, progress-size, or constraint faults. Apple framework service errors
listed above remain, along with a TextInputUI cancellation explicitly described
by macOS as benign unless unexpected. No new crash report appeared during this
verification. These observations cover the tested session, not a guarantee that
every possible runtime path is fault-free.

All 207 tests passed again after the search fix. Debug packaging and launch
succeeded, and `git diff --check` passed. Evidence: `swift-test-search-fix.log`,
`build-run-search-fix.log`, `unified-search-fix.log`, `search-fix-desktop.jpg`, and
`search-fix-narrow.jpg` under the ignored evidence directory above.
