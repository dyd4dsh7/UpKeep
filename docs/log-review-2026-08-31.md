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
