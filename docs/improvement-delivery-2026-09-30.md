# Codebase improvement delivery

Scope: all findings and recommendations in the 30 September review. Preserve the pre-existing formula verification edits. Local implementation and validation do not imply commit, push, deployment, or real package/app mutations.

## Completion evidence

- [x] Release and staged-bundle compatibility checks, fixture regressions
- [x] Shared bounded command runner, deadlines, cancellation, process fixtures
- [x] Individual and batch installed-state reconciliation, including partial command failures
- [x] Cleanup and install environment reservations, overlap regressions
- [x] Per-source attempt/success freshness and independent global scheduling
- [x] Menu-bar check health independent of update count
- [x] Complete Homebrew formula revision/version-scheme metadata
- [x] Honest cleanup measurements with unavailable/estimate states
- [x] Progressive source results and progress, generation ownership, latency evidence
- [x] Bounded global/per-host checks and foreground priority, concurrency evidence
- [ ] Scoped view observation, cached list/search projections, bounded icon cache, performance evidence
- [x] Cached history reads and controlled backup maintenance
- [ ] Operation centre with outcomes, phase, elapsed time, command log, retry and verification
- [ ] Source health UI and failed-source retry
- [ ] Homebrew dependency-impact and service/restart preview
- [ ] Recovery storage UI, sizes, versions, recovery records and byte budget
- [x] Ownership-focused store and manager-parser refactoring
- [ ] CI fixture UI smoke and performance trend checks; oldest-runtime coverage where available
- [ ] Final warnings-as-errors tests, packaging/startup, desktop/narrow UI and requirement audit

## Validation log

Implementation is in progress. No items are complete until verified against their scope.

### Current implementation checkpoint

Implemented and covered by local regressions: compatible Sparkle release selection and staged bundle policy; shared bounded command execution for package inventory/install clients; formula revision/version-scheme targets and exclusions; cleanup/install reservations; scoped cleanup measurements; attempt/success freshness and full-scan scheduling separation; menu-bar health; bounded icon and search caches; cached history decoding and explicit maintenance.

Formula updates now verify their targeted installed token before recording history. Exit-zero/no-change writes no update record. Nonzero/changed records the observed installed version and retains the command error. Cask, developer, model and batch reconciliation still require the same treatment.

Recovery storage now exposes allocated backup sizes, location, protected recovery records and a 5 GiB retention budget. Unknown size information is explicit; interrupted-update recovery backups remain protected even above budget. Added regressions for zero-budget saved-backup pruning and interrupted recovery protection. The new storage sheet still needs rendered UI verification.

252 tests passed with Swift warnings treated as errors using the macOS 26.5 SDK. The local toolchain emits linker search-path warnings for absent CommandLineTools directories; this is separate from Swift source warnings. `git diff --check` passed at this checkpoint. No commit, push, production mutation, packaged launch, rendered verification or CI run has been performed for these changes.

Remaining major work: complete reconciliation across all mutation paths; remaining command transports and descendant cancellation; progressive scans; global/per-host concurrency and priority; broader scoped observation; operation centre; source health and retry; dependency/service previews; ownership refactors; fixture UI/CI performance coverage; packaging/startup and desktop/narrow verification. All scope checkboxes remain open until their full evidence is available.

### Formula batch and worker cancellation checkpoint

Both formula batch entry points now share targeted verification and actual-version history with individual updates. Formula-only batches avoid a full global scan. The four outcome fixtures run across individual, unified-batch and Homebrew-all entry points and verify history ordering and installed-version results.

Direct app verification/unpacking and the publisher curl transport now use the shared dual-pipe, bounded-output command runner. Worker cancellation propagates to their active child command and prevents later commands; direct installation checks cancellation immediately before replacement. Disk-image detach cleanup has its own bounded execution so cancellation does not suppress cleanup. Descendant process-tree cancellation remains open. DNS resolution and synchronous file copies also remain bounded only by their underlying system calls.

253 tests pass with Swift warnings treated as errors, including synchronous worker cancellation and all formula batch outcome fixtures. `git diff --check` passes. Packaging, rendered UI and CI verification remain outstanding.

### Source health checkpoint

Settings now exposes per-source attempts, last success, failure details and retained-result state, with failed checks shown by default. App retries carry a source filter through the scanner and merge only that source's candidates, failures and freshness. Package-manager retries preserve other manager warnings. Developer and model scans persist scoped freshness, including failed model runtimes that returned no models.

Added a regression proving a Sparkle-only retry preserves GitHub candidates and freshness without advancing the app-wide check date. Full app refresh still clears obsolete source failures. Aggregate Homebrew/macOS and model retries, model-runtime failure recovery, and rendered verification remain open; the source-health scope is not yet complete.

### Homebrew impact checkpoint

The selected package's inspector now previews transitive installed dependencies, dependencies with available updates, packages that depend on it, unresolved dependencies and app/service restart guidance. This uses the loaded inventory and explicitly distinguishes it from Homebrew's final transaction; running services have not been inspected. Tests prove cycle handling, transitive reverse dependencies, missing dependencies and ambiguous tap-name resolution without confusing casks with formulae.

256 tests pass with Swift warnings treated as errors; `git diff --check` passes. Rendered verification is still outstanding. The existing launch script kills all processes named Upkeep and replaces `dist/Upkeep.app`; an isolated fixture launch needs separate app identity and dependencies before using it for UI smoke checks.

### Shared publisher concurrency checkpoint

Publisher checks and direct downloads now share an actor gate with eight global slots and two per host. Each redirect acquires its destination host's slot; held connections release their permit before redirecting. Full scans inherit background priority, while targeted checks/downloads use foreground priority. Foreground requests pass queued background requests, with fifteen-second aging to prevent background starvation. Cancellation removes queued requests; request errors release active capacity.

Deterministic concurrency fixtures prove global and same-host bounds, progress for other hosts behind a blocked host, foreground ordering, aging ordering, queued cancellation and error/retry capacity recovery. This proves publisher-request limits, not a full scan latency or UI performance improvement. Progressive publication, broader command/source scheduling, latency benchmarks and rendered verification remain outstanding.

260 tests pass with Swift warnings treated as errors. `git diff --check` passes. No live publisher traffic or installed-package mutations were used for these concurrency fixtures.

### Progressive app checks checkpoint

The scanner now publishes discovery and each completed app-source result through an async progress contract. App candidates can appear while unrelated source scans are still pending. The scan notice shows completed/total app-source checks; scan state captures time to first result. A generation token rejects stale progress, and source revisions preserve later targeted refresh candidates, failure state and freshness during both progressive publication and final report merging.

Non-app sources still publish at final completion. Their progressive payloads, timing diagnostics/benchmarks and rendered verification remain open. This is not yet completion of the whole progressive-source requirement.

261 tests pass with Swift warnings treated as errors, including a paused-scan regression that proves early publication and preservation of newer targeted candidates, installed metadata and freshness through late discovery/progress and final merging. `git diff --check` passes. Broader overlapping-scan/source ownership and warning/status merge coverage remain part of the open requirement.

### Ownership and failure-state checkpoint

Full-scan merging now preserves newer targeted failures in the summary and source warnings, and skips their app-wide success stamps. History is loaded before the final synchronous merge, preventing reentrancy midway through that merge. An older targeted app check is discarded after a newer full scan starts, and obsolete ownership entries are pruned at full-scan start. Regression scenarios cover both successful and failed newer targeted checks, plus an older targeted check that must not revive results after a newer full scan.

Ownership for developer/model/Homebrew scoped scans, grouped-warning coverage, non-app progress, timing measurements and rendered verification remain open.

262 tests pass with Swift warnings treated as errors; `git diff --check` passes. The new ownership regressions use injected, paused scans and perform no real package mutations.

### Model runtime and mutation verification checkpoint

The live model client supports scanning one runtime. Health rows can retry Ollama or LM Studio independently; successful empty runtime checks clear earlier runtime failures. Scoped merging retains other runtimes' models and freshness. Tests prove this on both successful and failed retries.

Individual and batch model mutations now rescan the selected runtime on both command success and failure. History records the observed installed revision only when it changed. Unchanged, missing and unverifiable results create no update history. A changed revision after command failure is recorded while the command error remains visible. Model-only batches do not overwrite these results with an unrelated full scan; their result messages show the observed revision.

Remaining ownership and concurrent-operation coverage for model scans, plus rendered retry verification, stays open.

264 tests pass with Swift warnings treated as errors; `git diff --check` passes. The model regressions cover five command/verification outcomes through individual and batch entry points using injected clients.

### Model runtime reservations checkpoint

Scoped model scans and model mutations now reserve their runtime as well as each model ID. Same-runtime scans/updates cannot overlap; nested verification keeps the originating mutation's ownership. Ollama and LM Studio use separate scan operation IDs and can progress independently. Shared-runtime reservations disable conflicting actions without displaying another model's active phase.

Added a paused-update regression proving that another Ollama update and scan are blocked while an LM Studio update can finish, then the first Ollama update verifies successfully and releases its reservation. Full global scanner ownership for model results remains open.

265 tests pass with Swift warnings treated as errors; `git diff --check` passes. The reservation test uses injected clients and performs no real model downloads.

### Individual developer-install verification checkpoint

Individual developer installs now rescan their manager after both command success and failure, identify the exact package/environment ID and write observed-version history only when the installed version changed. Unchanged and unverifiable results create no history. Changes after command failure retain the command error; a different installed version is recorded accurately and flagged against the requested version. Packages from other managers are preserved and no unrelated full scan is required.

Added regression outcomes for successful, unchanged, partial, unverifiable and unexpected-version installs. Unified developer-batch verification and broader scan ownership remain open.

266 tests pass with Swift warnings treated as errors; `git diff --check` passes. The new install regressions use injected clients and do not mutate installed packages.

### Shared developer batch verification checkpoint

Unified developer batches now use the individual verified-install path rather than saving the requested version immediately after command success. Five command/verification outcomes run through both individual and batch entry points. Developer-only batches keep the verified manager results without an unrelated global scan, and successful result messages show observed installed versions. Partial-failure messages explicitly state the installed version alongside the command error.

The full 266-test suite passed for the shared batch path. The focused developer outcome suite passed all ten individual/batch cases after the final message adjustment; `git diff --check` passes. Broader ownership, cask verification, operation centre, UI and packaging requirements remain open.

### Individual cask bundle verification checkpoint

Individual cask updates now inspect the installed bundle after both successful and failed Homebrew commands. History records the observed installed version only when the bundle version or build changed. Unchanged installations create no success history; unverifiable installations retain their recovery backup and report the verification failure. An installed change after a command failure is recorded with the command error retained. The cask's pending-update state is recalculated from the observed bundle version and build.

Updated the transaction fixture to expose its actual installed bundle change and added successful, unchanged, partial-failure and unverifiable-bundle regression cases. All 267 tests pass with Swift warnings treated as errors; `git diff --check` passes. These checks use injected clients and do not change installed applications. Cask batch/all-update and adoption paths still need the same reconciliation, and rendered UI, packaging and the remaining review requirements remain open.

### Shared Homebrew batch verification checkpoint

Homebrew batch items and the Homebrew update-all loop now use the individual verified mutation path for both formulae and casks. They no longer save requested-version history solely because the command exited successfully or discard a recovery backup solely because the command failed. Homebrew-only unified batches retain their targeted verified results without triggering an unrelated full scan.

The cask outcome regression now runs all four outcomes through individual, unified-batch and update-all entry points (12 cases). All 267 tests pass with Swift warnings treated as errors; `git diff --check` passes. Adoption and application fallback cask paths, wider scan ownership, rendered UI and packaging remain open.

### Adoptable application update verification checkpoint

Updating an adoptable application now verifies its installed bundle after both command success and failure using the shared cask reconciliation. History records observed changes; unverifiable results retain recovery backups. A verified successful update removes the obsolete adoption offer. Plain adoption and unified application fallback paths remain open.

The cask outcome regression now covers this fourth entry point, for 16 cases across successful, unchanged, partially failed and unverifiable results. All 267 tests pass with Swift warnings treated as errors; `git diff --check` passes. No real application mutation was performed.

### Application batch cask fallback checkpoint

Unified application batches now use verified reconciliation when replacing an adoptable application or upgrading a cask token absent from the package inventory. Both command outcomes inspect the installed bundle, protect unverified recovery backups and record only observed changes. Successful Homebrew application batch items no longer trigger an unrelated full scan.

The cask regression now covers six entry points and four outcomes (24 cases). All 267 tests pass with Swift warnings treated as errors; `git diff --check` passes. Plain adoption, direct-installer post-mutation reconciliation, broader scan ownership, rendered UI and packaging remain open.

### Observed Homebrew batch version checkpoint

Successful Homebrew package and application batch results now show the installed version from verified state. Added a newer-than-requested outcome through all six cask entry points, checking observed history versions and batch result messages. The cask regression covers 30 cases, and all 267 tests pass with Swift warnings treated as errors. `git diff --check` passes. Remaining implementation and rendered/package verification requirements are unchanged.

### Plain adoption receipt verification checkpoint

Plain adoption now rereads the exact Homebrew cask receipt after both command outcomes. Confirmed registration updates the package inventory and removes the adoption offer, including a registration observed after a command failure; that failure remains visible. Missing or unavailable receipts retain the adoption offer and report unverified status. Adoption creates no invented version-update history and does not require an unrelated full scan.

Added four registration outcomes using injected clients. All 268 tests pass with Swift warnings treated as errors; `git diff --check` passes. Direct-installer reconciliation and the broader implementation/UI/package requirements remain open.

### Individual application fallback cask checkpoint

The individual application update action for a Homebrew token absent from the package inventory now uses the same installed-bundle reconciliation as other cask actions. Removed its command-only history write, full scan and unconditional failure backup disposal. The cask regression now covers seven entry points and five outcomes (35 cases), including this fallback action and newer-than-requested installations.

All 268 tests pass with Swift warnings treated as errors; `git diff --check` passes. Direct-installer reconciliation and the remaining review requirements stay open.

### Shared installation observation policy checkpoint

Added AppInstallationVerification and applied it to cask reconciliation. It rejects missing bundles, mismatched identifiers/locations and empty installed versions; distinguishes unchanged bundles from observed changes; and evaluates requested marketing versions and build-only targets separately. This provides the shared policy for pending direct-installer reconciliation.

All 269 tests pass with Swift warnings treated as errors. The focused policy regression also passes after adding wrong-identity and empty-version cases; `git diff --check` passes. Direct installer integration, broader scan ownership, operation centre, performance measurement, UI and packaging remain open.

### Individual direct installation reconciliation checkpoint

Individual direct installs now reread the installed bundle after either installer outcome and apply the shared observation policy. Unchanged installations create no update history; unavailable verification retains the recovery backup. Observed changes record their actual installed version even after a command failure, which remains visible. Verified bundles replace the app snapshot and prune obsolete update candidates without an unrelated full scan. An observed change below the requested target remains flagged.

Added five installation outcomes using injected clients and updated the progress fixture to expose its installed bundle change. All 270 tests pass with Swift warnings treated as errors; `git diff --check` passes. Direct batch integration, build-aware history details, broader ownership, UI and packaging remain open.

### Shared direct batch reconciliation checkpoint

Direct application batch items now use the individual post-install bundle verification after either installer outcome. They record observed versions, retain unverifiable recovery backups and reject unchanged/incomplete installations. Verified installations with history-save failures remain updated with an explicit warning. Batch result messages show observed installed versions. Removed the obsolete post-batch full scan because every automatic batch mutation now reconciles its own source result.

The full 270-test suite passed with Swift warnings treated as errors. After removing the obsolete branch, the focused direct outcome and history-warning suites passed (ten individual/batch outcome cases plus history failure). `git diff --check` passes. Broader scan ownership, build-aware history, operation centre, performance, UI and packaging remain open.

### Build-aware history checkpoint

Application history records now preserve optional installed build numbers before and after direct/cask mutations. Recovery manifests include the backed-up build. History transitions and restore labels display build numbers when available, so equal marketing versions can show a build-only change. Older JSON records without these fields remain decodable.

Added JSON round-trip, legacy-record and build-label regression checks. All 271 tests pass with Swift warnings treated as errors; `git diff --check` passes. Rendered history verification, wider ownership, operation centre, performance and packaging remain open.

### Observed recovery manifest checkpoint

Saving application history now atomically refreshes its managed recovery manifest with observed versions/builds before committing normal history. If normal history cannot be read or written, relaunch retains the actual installed result and its protected backup rather than the originally requested target. Successful history commits still remove the temporary recovery manifest.

Extended the real filesystem persistence-failure regression to verify observed marketing/build versions across relaunch and cleanup. All 271 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader implementation and rendered/package verification remain open.

### Homebrew package health retry checkpoint

Targeted Homebrew package refreshes now record source attempts, success and missing/unavailable receipt failures. Source health offers a scoped retry for package keys still present in inventory and disables it during that package's refresh. Aggregate Homebrew/catalogue and macOS retry entry points remain open.

The full 271-test suite passed for the implementation. Added a focused regression covering successful, missing and unavailable receipts without advancing the global scan schedule; all three cases pass. `git diff --check` passes. Rendered retry verification and broader implementation/package requirements remain open.

### Scoped Homebrew inventory retry checkpoint

Added a scanner inventory entry point backed directly by Homebrew inventory, with no application discovery or unrelated source checks. Source health now retries Homebrew inventory through a dedicated operation and a Homebrew environment reservation. Failure retains the existing package inventory and records health; success replaces inventory and records success without advancing global scheduling. Scanner implementations without this capability report an explicit unsupported scoped-check error.

The full 272-test suite passed for the implementation. Added focused success/failure retry regressions; both pass. `git diff --check` passes. Catalogue/macOS retries, ownership against overlapping full scans, candidate reconciliation, rendered UI and the wider requirements remain open.

### Scoped Homebrew catalogue retry checkpoint

Added a dedicated catalogue scanner entry point and source-health retry. It rebuilds adoption offers from the current app and package snapshots without discovering applications or checking unrelated sources. Failure retains previous offers and records source health; success replaces offers without advancing the global schedule. Catalogue and inventory retries reserve the Homebrew environment.

Added success/failure catalogue regressions checking retained offers, unchanged app/package inventory and independent scheduling. All 274 tests pass with Swift warnings treated as errors; `git diff --check` passes. macOS retries, full-scan ownership, candidate reconciliation, rendered UI and broader delivery remain open.

### Scoped macOS retry checkpoint

Added separate macOS update/installers scanner entry points and source-health retry controls. The live client invokes only the selected softwareupdate listing. Each retry preserves the other list and retains its selected results on failure; source health records success/failure without advancing global scheduling. Older scanner implementations report an explicit unsupported scoped-check error.

The full 274-test suite passed for the implementation. Added focused update/installers success/failure regressions; all four cases pass. `git diff --check` passes. Full-scan ownership, current-system metadata/warning reconciliation, rendered retries and broader implementation/package requirements remain open.

### macOS retry warning/status reconciliation checkpoint

Scoped macOS retries now clear or replace only their corresponding update/installers warning. Failed retries always have an actionable fallback message; update retries refresh the macOS check status. Successful results obey the prerelease setting while preserving the other list. Extended the four scoped retry cases to assert warning isolation and check status.

All 275 tests pass with Swift warnings treated as errors; `git diff --check` passes. System metadata policy, full-scan ownership, rendered retries and broader delivery remain open.

### Superseded aggregate retry checkpoint

Scoped Homebrew inventory/catalogue and macOS updates/installers retries now capture full-scan ownership before awaiting their source. A newer full scan supersedes that retry's success or failure, preventing the older response from changing inventory, source health, warnings or errors. Operation cleanup still releases reservations/activity state.

Added eight paused-response cases across the four sources and both outcomes. All 276 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader mutation/full-scan ownership, candidate reconciliation, rendered UI, performance and packaging remain open.

### Inventory retry candidate reconciliation checkpoint

Successful Homebrew inventory retries now reconcile packages against installed app snapshots, replace Homebrew application candidates from the refreshed inventory and retain candidates from other sources. Non-outdated/missing casks lose obsolete offers, and registered cask tokens remove obsolete adoption offers. Failed inventory retries continue retaining known results.

Added outdated/current cask regression cases proving stale-version removal and preservation of Sparkle candidates. All 277 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader ownership, scoped warnings, performance, rendered UI and packaging remain open.

### Homebrew scoped warning reconciliation checkpoint

Full scans label inventory warnings separately from catalogue warnings. Scoped retries clear/replace only the corresponding warning and preserve failures from the other source. Homebrew update-all success now depends on its individual verified mutations and remaining attempted packages, rather than unrelated aggregate warnings.

Extended inventory success/failure regressions to prove warning isolation and the cask update-all outcomes to run with an unrelated catalogue failure. All 277 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader ownership, performance, operation centre, rendered UI and packaging remain open.

### Progressive Homebrew inventory checkpoint

The full scanner now publishes successful Homebrew inventory as soon as that source completes, independently of application discovery and slower sources. The store exposes the package inventory during the scan and records time to the first completed result. The existing scan generation guard applies to inventory events. Final report reconciliation remains authoritative.

Added a paused-scan regression proving inventory is visible before scan completion and activity clears afterward. All 278 tests pass with Swift warnings treated as errors; `git diff --check` passes. Progressive catalogue/macOS/developer/model delivery, broader ownership, latency benchmarking, operation centre, rendered UI and packaging remain open.

### Progressive macOS source checkpoint

Full scans now publish macOS source results as soon as their check completes, while other sources remain active. The store replaces successful update/installers scopes and retains previously known entries for failed scopes, applies captured prerelease/installer settings and records time to the first completed result. Final report reconciliation remains authoritative.

Added paused-response cases for an update failure and an installer failure, proving early fresh results and retained entries coexist. All 279 tests pass with Swift warnings treated as errors; `git diff --check` passes. Progressive catalogue/developer/models, broader ownership, latency benchmarking, operation centre, rendered UI and packaging remain open.

### Progressive developer source checkpoint

Full scans now publish developer package reports as soon as their source completes. Progressive reconciliation replaces the checked managers' successful environments, retains packages from failed managers/executables and leaves unrelated managers intact until final reconciliation. Installed manager metadata refreshes with the report, and first-result timing includes this source.

Added a paused-scan regression proving fresh npm packages and retained failed pipx packages are visible together before completion. All 280 tests pass with Swift warnings treated as errors; `git diff --check` passes. Progressive catalogue/models, broader ownership, latency benchmarking, operation centre, rendered UI and packaging remain open.

### Progressive local-model source checkpoint

Full scans now publish local-model reports when that source completes. Progressive reconciliation accepts refreshed models, retains known entries for failed model IDs/runtimes, maintains a valid selection and records first-result timing. Final report reconciliation remains authoritative.

Added a paused-scan regression proving fresh LM Studio models and retained failed Ollama models appear together before full completion. All 281 tests pass with Swift warnings treated as errors; `git diff --check` passes. Progressive catalogue/per-runtime delivery, broader ownership, latency benchmarking, operation centre, rendered UI and packaging remain open.

### Model runtime scan ownership checkpoint

Targeted model checks now claim runtime/model revisions. An older full scan preserves models belonging to later targeted checks during progressive and final publication, and does not replace their check timestamps or freshness. An earlier targeted check superseded by a newer full scan returns without committing stale results. Full freshness recording also skips model IDs within protected runtimes.

Added a paused-full-scan regression proving a newer Ollama check retains its models and freshness after full completion. The full 282-test suite passed; the focused ownership test passed after the final freshness adjustment. Swift warnings are treated as errors and `git diff --check` passes. Warning/status reconciliation, additional ownership race cases, developer ownership, UI, performance and packaging remain open.

### Developer manager scan ownership checkpoint

Targeted developer-manager checks now claim source revisions. An older full scan preserves later targeted packages and installed-manager metadata during progressive and final publication, and does not replace their successful check timestamps or freshness. An earlier manager check superseded by a newer full scan returns without committing stale state.

Added a paused-full-scan regression proving a newer npm check retains its packages, manager metadata and freshness after full completion. All 283 tests pass with Swift warnings treated as errors; `git diff --check` passes. Mutation ownership, warning/status reconciliation, additional races, operation centre, performance, rendered UI and packaging remain open.

### Verified developer mutation ownership checkpoint

Developer install verification now claims the manager revision after the installed-state rescan completes. Older full-scan progressive/final results cannot replace the verified installed packages or their source freshness. This applies to a successful command and an observed installation after command failure.

Added two paused-full-scan mutation cases proving observed versions/history and freshness survive full completion. All 284 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader mutation ownership, warning/status reconciliation, operation centre, performance, rendered UI and packaging remain open.

### Protected source warning/status checkpoint

Full-scan warning reconciliation now removes superseded named developer-manager/model-runtime warning entries and restores failures from protected source freshness. A full scan cannot report complete when a newer protected check failed; its summary becomes partial. Unscoped aggregate warnings remain retained when their affected environment cannot be identified.

Added developer/model paused-full-scan failure cases verifying retained warnings and partial status. All 285 tests pass with Swift warnings treated as errors; `git diff --check` passes. Structured aggregate warning attribution, broader ownership, operation centre, performance, rendered UI and packaging remain open.

### Structured aggregate warning attribution checkpoint

Live developer/model clients now attach the producing manager/runtime to each warning when combining source results. Shared warning text retains every producing environment. Full scans convert that metadata into named warning entries, preserving attribution through existing aggregation and protected-source reconciliation. Reports without attribution remain explicitly unscoped rather than inferring a source from message text.

Added manager/runtime attribution and unknown-scope regression checks. All 286 tests pass with Swift warnings treated as errors; `git diff --check` passes. Targeted whole-source warning propagation, broader ownership, operation centre, performance, rendered UI and packaging remain open.

### Scoped retry warning reconciliation checkpoint

Targeted developer-manager and model-runtime checks now preserve report attribution. A scoped retry removes only the checked environment from shared warnings, retains unrelated and unknown failures, and combines repeated shared messages into one warning identity. Whole-source checks keep fresh explicit attribution.

Four regression cases cover shared failures, whole-source attribution, unlisted affected environments and repeated warning identity. All 290 tests pass with Swift warnings treated as errors; `git diff --check` passes. Broader ownership, operation centre, performance, rendered UI and packaging remain open.

### Verified app installation ownership checkpoint

Direct and cask bundle verification now claims the installed app state across update sources before asynchronous history work. Older full-scan discovery and source results preserve the observed installed version/build and cannot revive an already-satisfied app candidate. Verified state also takes precedence when an installer reported failure after changing the bundle.

Added a paused-full-scan installation regression covering successful and failed command outcomes. All 291 tests pass with Swift warnings treated as errors; `git diff --check` passes. Homebrew inventory mutation ownership, additional races, operation centre, performance, rendered UI and packaging remain open.

### Verified Homebrew receipt ownership checkpoint

Individual verified package replacements now claim receipt revisions. Older progressive inventory and final full-scan results retain these newer packages, including when the full report omits them. Full-scan check timestamps skip protected package receipts.

Added a paused inventory regression proving a verified formula upgrade remains current through repeated stale progressive inventory and full completion. All 292 tests pass with Swift warnings treated as errors; `git diff --check` passes. Additional cask/catalog ownership races, operation centre, performance, rendered UI and packaging remain open.

### Verified adoption catalogue ownership checkpoint

Final catalogue publication now removes adoption offers for casks in the reconciled installed inventory, including receipts protected from an older full scan. A successful registration, or registration followed by a command error, cannot regain a stale adoption offer.

Added paused full-scan registration cases for both command outcomes. All 293 tests pass with Swift warnings treated as errors; `git diff --check` passes. Additional ownership races, operation centre, performance, rendered UI and packaging remain open.

### Operation centre live activity checkpoint

Added a toolbar Operations sheet observing the dedicated execution state. Active updates display their item, current phase and elapsed time; phase changes preserve the activity start time. The empty state is explicit.

All 293 tests pass with Swift warnings treated as errors; `git diff --check` passes. This is the live-activity foundation only: completed verified outcomes, command logs, retry/verification controls and rendered desktop/narrow verification remain open, alongside the remaining broader review scope.

### Operation centre completed verification checkpoint

Completed activity is retained in a bounded 100-record session list with stable item labels and elapsed duration. Direct/cask bundle verification and formula receipt verification explicitly distinguish changed, unchanged and unavailable installed state; uninstrumented paths remain unavailable rather than inferring success from command exit. Repeated end calls cannot duplicate completion records.

Extended successful/partial direct-install regressions to assert verified-change outcomes. All 293 tests pass with Swift warnings treated as errors; `git diff --check` passes. Developer/model/adoption outcome wiring, target satisfaction and command failure details, command logs, retry/verification controls, rendered verification and broader scope remain open.

### Operation centre remaining update outcomes checkpoint

Developer and model updates now record observed change/unchanged/unavailable verification outcomes, and adoption records verified registration. Completed records retain command errors separately from the installed-state outcome; partial changes remain visible without claiming the command succeeded. Formula/adoption/developer/model paths preserve command errors when verification is unavailable.

Extended developer/model individual and batch outcome fixtures and adoption fixtures to assert operation results and partial-command details. All 293 tests pass with Swift warnings treated as errors; `git diff --check` passes. Target-satisfaction details, command logs, retry/verification controls, rendered verification and the broader review scope remain open.

### Operation centre target satisfaction checkpoint

Completed verified app/cask/formula/developer/model updates now retain requested and observed versions, plus whether the original requested target was reached. App targets share the existing marketing/build comparison policy; developer versions require the requested version, model revisions require the requested revision. Unavailable verification does not invent a target result. The operation sheet displays target status separately from installed change and command errors.

Extended direct-install and developer individual/batch fixtures to prove reached, unexpected-version and unavailable states. All 293 tests pass with Swift warnings treated as errors; `git diff --check` passes. Command logs, retry/verification controls, rendered UI and broader scope remain open.

### Operation centre scoped verification controls checkpoint

Recent operations now provide Check again using the current app/package identity and existing scoped app, package, developer-manager or model-runtime checks. Missing targets and active updates disable the action; the sheet prevents duplicate requests. Rechecking does not replay a mutation or rewrite the original operation outcome.

Added an integration regression proving a completed developer operation checks its manager again without creating a second update/history entry, and a removed target cannot trigger another check. All 294 tests pass with Swift warnings treated as errors; `git diff --check` passes. Mutation retry controls, operation command logs, rendered UI and broader scope remain open.

### Operation centre mutation retry checkpoint

Recent operations now offer Retry current update only when a current eligible unsatisfied target exists. Retry resolves current library identities and enters existing public update/adoption methods, preserving authorization, running-app confirmation and mutation reservations. The operations sheet dismisses before a retry so existing confirmation surfaces remain available.

Added an integration regression proving cask retry requests authorization without executing a mutation and a satisfied target cannot retry. All 295 tests pass with Swift warnings treated as errors; `git diff --check` passes. Per-operation command logs, rendered UI and broader review scope remain open.

### Operation centre command log checkpoint

Update command execution now uses a per-operation task-local log, explicitly propagated through the runner's dispatch queue and the direct installer's detached worker. Logs retain executable/arguments, exit status, bounded output or command failure. Existing diagnostic redaction and credential-flag redaction apply before retention; truncated logs are labelled. Completed operations expose an expandable command log, with an explicit unavailable-output state. Retention is bounded per command and per operation.

Added independent concurrent-command log isolation, redaction/retention bounds, and completed app-operation log integration regressions. All 298 tests pass with Swift warnings treated as errors; `git diff --check` passes. Terminal-assisted Homebrew commands and other detached transport propagation, failure partial-output capture, rendered UI, and the broader review scope remain open.

### Interrupted and Terminal command log checkpoint

The command runner now records buffered output and termination status before throwing timeout/cancellation/output-limit failures. Terminal-assisted Homebrew commands capture bounded output and status before temporary files are removed; missing status/output is explicit. Homebrew adoption's detached permission-repair worker propagates the operation log context.

Added timeout partial-output and Terminal-file status/redaction fixtures. All 300 tests pass with Swift warnings treated as errors; `git diff --check` passes. No live Terminal/Homebrew mutation was run. Rendered operation-centre verification, additional transport/context coverage and the broader review scope remain open.

### Isolated fixture launch and first rendered checkpoint

Added a debug-only --ui-fixture startup with unique settings and mock services for every injected external action. Fixture mutation paths reject updates, cleanup, restores, opening URLs and quitting applications. Added a separate temporary bundle packager with distinct bundle/executable identity; it does not kill processes or replace dist/installed applications.

All 301 tests pass with Swift warnings treated as errors, including fixture mutation rejection; shell syntax and `git diff --check` pass. The temporary fixture bundle signature verifies. Sandboxed Launch Services reported a missing executable and direct startup aborted; an approved host launch succeeded. Native UI inspection confirmed the fixture Updates route and rendered Operations sheet, including requested/installed versions, target status, command error and action labels.

Rendered inspection exposed combined list-row accessibility for command-log/check/retry controls. Individual control accessibility, interactions, narrow layout, additional fixture states, other routes, CI smoke integration and the broader scope remain open. Fixture bundle: /private/tmp/upkeep-ui-fixture.jg2NN0/Upkeep UI Fixture.app.

### Operation centre accessibility and interaction checkpoint

Replaced recent-operation List rows with scrolling cards after native inspection proved accessibility containment alone did not expose child controls. Command disclosure, Check again and Retry current update now appear as separate native accessibility elements. Fixture bundle identity activates mock mode even when reopened without arguments.

All 301 tests pass with Swift warnings treated as errors; `git diff --check` passes. Native fixture inspection verified separate controls, expanded captured command text/status, completed scoped recheck, and retry dismissing Operations before displaying the fixture mutation-rejection alert. No live mutation occurred. Two native drag resize attempts did not change window dimensions; narrow verification remains open and requires a reliable fixture launch-size path. Latest fixture bundle: /private/tmp/upkeep-ui-fixture.TRB6DB/Upkeep UI Fixture.app.

Narrow and additional operation states, other routes, CI fixture smoke, performance evidence and broader scope remain open.

### Reproducible narrow fixture verification checkpoint

Added --ui-fixture-narrow to select the supported 760-point window width and 500-point content height. Each fixture package now has a unique mock-recognized bundle identity so restored window dimensions do not override the requested launch size.

All 301 tests pass with Swift warnings treated as errors; packager shell syntax and `git diff --check` pass. Native screenshots verified the Updates route at 760-point width (1520-pixel Retina capture) with adapted review banner and item controls. The Operations sheet and expanded command log fit the narrow host window, with Done, Check again and Retry current update independently exposed and visible. This verifies the seeded completed-operation state only; active/empty/long-output/multiple-result states, other routes, CI fixture smoke, performance evidence and broader scope remain open. Fixture: /private/tmp/upkeep-ui-fixture.j9zVff/Upkeep UI Fixture.app.

### Active, empty and long-log rendered checkpoint

Added explicit debug fixture operation states through --ui-fixture-state=active|empty|longLog. Active state seeds a downloading operation alongside a recent result; empty removes recent results; longLog seeds long lines and enough output to require scrolling.

All 301 tests pass with Swift warnings treated as errors; `git diff --check` passes. Native narrow-window inspection verified downloading phase/elapsed duration with recheck disabled during the active operation, an explicit empty state with Done, and wrapped long command output. AXScrollToBottom and screenshots proved Check again and Retry remain reachable below the long output. Active and recent content use independent scrolling regions; compacting their layout remains an improvement opportunity. Native app discovery was slow for the first fixture but binding succeeded; this is tool latency rather than measured app startup performance.

Additional operation result combinations/multiple records, other routes, CI smoke, performance measurements, remaining codebase requirements and final audit remain open. State bundles: /private/tmp/upkeep-ui-fixture.ds7gfS, /private/tmp/upkeep-ui-fixture.QHOndp, /private/tmp/upkeep-ui-fixture.nHNmlV.

### Offline benchmark and CI evidence checkpoint

Changed CI's launch smoke command to debug fixture dependencies at narrow width with active-operation state. Added offline release responsiveness/service/paired-search measurement steps, a paired-search summary, and retained performance artifacts. The fixture packager now also handles standard SwiftPM debug output layout.

Workflow YAML parses, shell syntax checks and `git diff --check` pass. The local warnings-as-errors release responsiveness benchmark passed, producing seven post-warm-up samples at 200 and 2,000 items. Median lookup passes were 0.271/2.729 ms; primary count reads 0.085/0.829 ms; inventory reassignment 0.446/4.152 ms. Raw samples and limitations are documented under docs/performance/2026-10-01-responsiveness.*. Matching checksums permit a dated snapshot comparison, but environment/time differences prevent causal speedup claims.

No remote CI run occurred. Automatic regression gates, rendered CI assertions, service/search measurements for the current tree, oldest-runtime coverage and broader scope remain open.

### Current service and paired-search evidence checkpoint

Ran the offline service and paired-search benchmarks together in release mode with Swift warnings treated as errors. Both selected tests passed. Saved complete post-warm-up sample sets and an evidence/limitations report under docs/performance/2026-10-01-service-search.md and associated raw files.

Paired search alternates reference/optimized order and checks identities/order; at 2,000 items current fixture reductions ranged from 11.8% to 26.1% across name/missing/source/dependency queries. Service medians and dated snapshot differences are recorded without attributing cross-run differences to current changes. `git diff --check` passes.

Rendered responsiveness, progressive source latency evidence, current icon/history performance, automatic trend gates, remote CI and remaining review requirements remain open.

### Independent developer-manager publication checkpoint

The live developer client now groups detected environments by manager, scans managers concurrently, and publishes each manager after its own environments and optional prerelease enrichment finish. A slow manager no longer delays publication of every other manager. Enabled but absent managers publish empty results so stale inventory can be cleared. Aggregate results retain environment failure paths, failed-manager scopes and shared-warning ownership; existing injected clients retain a compatible whole-group progress fallback.

The scanner forwards manager-scoped results as they arrive. Added regressions for callback delivery before the developer scan returns and aggregation of partial environment failures/shared warning owners. All 303 tests pass with Swift warnings treated as errors; `git diff --check` passes. This proves the callback contract and aggregate preservation, not measured live-manager latency or rendered timing. Per-runtime model publication, scan latency fixtures, remaining review requirements and final audit remain open.

### Independent model-runtime publication checkpoint

The live model client now publishes Ollama and LM Studio results as each runtime finishes, while still returning the combined report. Progress events carry the checked runtime scope. Store merging preserves unchecked runtimes, failed model/runtime inventory and newer targeted runtime ownership; an empty successful runtime result clears only that runtime. Existing injected clients retain a whole-inventory fallback.

All 303 tests pass with Swift warnings treated as errors, including parameterized paused-scan coverage for both failed-runtime retention and unchecked-runtime retention while the full scan is still active. `git diff --check` passes. Actual live-runtime latency, scanner callback timing fixtures, rendered progressive behavior and the broader delivery audit remain open.

### Cross-source scheduling evidence checkpoint

Added an offline scanner regression with Homebrew inventory delayed by 250 ms. It records whether app-source, developer-manager, Ollama and LM Studio progress callbacks occur before that inventory finishes, and verifies the final app update remains in the aggregate report. All four source scopes published before Homebrew completed. All 304 tests pass with Swift warnings treated as errors; `git diff --check` passes.

This controlled delay proves cross-source scheduling independence under the fixture, not live source latency, UI frame timing or whole-scan speedup. Live timing/rendered progressive verification, process-descendant cancellation, service inventory, broader reservations/refactoring and remaining delivery requirements stay open.

### Bounded-output diagnostic preservation checkpoint

Inspection of command cancellation confirmed that Control still signals only its immediate Process. Descendant ownership/cancellation remains incomplete; the macOS SDK exposes child-process enumeration, but enumeration alone does not prove safe ownership across reparenting and PID reuse.

Fixed a separate concrete output-limit defect: a read larger than remaining capacity previously discarded its entire chunk. The runner now retains the bounded prefix in the appropriate stream and combined output before stopping the producer. Added a fixture proving useful stderr context survives an oversized first read into the operation log. All 305 tests pass with Swift warnings treated as errors; `git diff --check` passes. Descendant cancellation and remaining delivery requirements remain open.

### Inventory-parser ownership checkpoint

Extracted twenty pure inventory parsers into DeveloperInventoryParsers, with private Nix-path/revision helpers and private Yarn/.NET decoding schemas. Command scans and version fixtures now call that explicit namespace. This removes the extracted formats' global parser entry points from the large command client without changing format behavior or command execution.

The first compile exposed Yarn's file-private schema dependency; moved that schema alongside its parser and reran the suite successfully. All 305 tests pass with Swift warnings treated as errors; `git diff --check` passes. Remaining manager parsing/transport ownership, store refactoring and the broader requirements stay open. No performance improvement is claimed from this structural extraction.

### Ruby inventory boundary checkpoint

Moved Ruby installed/outdated format parsing into DeveloperInventoryParsers. The command scan now owns command exit/failure handling and delegates only decoding and package construction. Added a format fixture covering default gems, multiple installed versions, outdated targets, malformed lines and executable identity. All 306 tests pass with Swift warnings treated as errors; `git diff --check` passes. Other manager transport/parser ownership, store refactoring and the remaining review scope stay open.

### Targeted model fallback warning isolation checkpoint

The LocalModelManaging default targeted scan previously filtered models but retained unrelated runtime warnings and discarded their ownership map. It now excludes warnings explicitly owned only by another runtime, intersects shared warning owners with the checked runtime, retains unattributed warnings conservatively, and restricts failed model identities to the scoped inventory. Runtime failure scopes remain intersected with the checked runtime. The live client's explicit targeted implementation is unchanged.

Added a mixed-runtime fixture proving model identities, per-model failures, runtime failures, shared warnings and unknown warning preservation. All 307 tests pass with Swift warnings treated as errors; `git diff --check` passes. Full source-health rendered verification and remaining delivery requirements stay open.

### Homebrew service inventory foundation checkpoint

Added a read-only HomebrewClient.services command using `brew services list --json` without sudo. Homebrew's official manual describes current-user managed-service inventory; its published source documents JSON fields name/status/user/file/exit_code and an empty array when no services exist. Sources: https://docs.brew.sh/Manpage and https://docs.brew.sh/rubydoc/Homebrew/Cmd/Services/ListSubcommand.html.

The decoder retains unknown status strings and optional user/file/exit codes. Missing Homebrew or unreadable command/JSON output raises a failure instead of implying no running services. Fixtures cover started/error/unknown statuses, optional fields, empty inventory and malformed records. All 308 tests pass with Swift warnings treated as errors; `git diff --check` passes. No live service command was run. Dependency injection, store state/freshness, impact-preview matching and rendered verification remain to connect this foundation to the user feature.

### Injectable service refresh checkpoint

Added service inventory to HomebrewManaging with an unavailable default for clients without that capability. Upkeep library state tracks inventory, attempt time, last successful time, failure details and an in-flight flag. The explicit store refresh prevents overlapping calls, retains old inventory/last success after failure, and accepts successful empty results as a cleared inventory.

Parameterized store fixtures verify success and failure behavior with no live Homebrew command. All 309 tests pass with Swift warnings treated as errors; `git diff --check` passes. Impact matching, UI refresh controls/freshness labels, rendered verification and the remaining delivery scope stay open.

### Service-to-impact matching checkpoint

HomebrewImpact now resolves observed services through the same exact-token/unique-short-name formula rules as dependencies. It exposes related services for the selected formula, its dependents and outdated installed dependencies. Casks do not masquerade as service formulae. Unresolvable or ambiguous service names are kept separately; no status or relationship is inferred from a shared short name.

Added a dependency/service fixture covering a unique tapped dependent, unrelated service and ambiguous tap names. All 310 tests pass with Swift warnings treated as errors; `git diff --check` passes. The preview still needs UI service rows, refresh/freshness/failure controls and rendered verification; this match is a loaded-graph preview, not a guarantee of Homebrew's final transaction or restart needs.

### Service preview controls checkpoint

Connected HomebrewImpactView to observed service state. The expanded impact preview offers an explicit Check services button, prevents overlapping checks, names the current-user scope, shows the last successful check, and labels retained results after failure. Related service rows preserve observed status and nonzero exit codes; started services receive conditional restart guidance. Unknown/unresolved service names and the not-yet-checked state remain explicit.

All 310 tests pass with Swift warnings treated as errors; `git diff --check` passes. No live service check was performed. Desktop/narrow rendering, fixture service states, interaction verification and remaining delivery requirements stay open; static compilation does not verify rendered usability.

### Offline service UI fixture checkpoint

Added --ui-fixture-state=services with an outdated fixture formula selected on the Homebrew route and a mock started service returned by explicit checks. The fixture Homebrew client implements service reads directly, so no live service command can run through that route. A fixture regression verifies route selection, package identity and mock service results. The initial compile caught a sidebar case mismatch; corrected it to homebrewPackages and reran successfully.

All 311 tests pass with Swift warnings treated as errors; `git diff --check` passes. Packaged the current debug fixture at /private/tmp/upkeep-ui-fixture.i6OW5d/Upkeep UI Fixture.app. Native launch, desktop/narrow preview rendering, failure-state fixtures and interaction verification remain open.

### Service fixture launch correction checkpoint

Native launch of the service fixture succeeded, but its AX tree showed Homebrew with zero installed packages: the automatic startup mock scan replaced the seeded formula with an empty inventory. Updated the mock scan report to return the fixture formula with successful inventory status, and extended the fixture regression to scan before checking service results.

All 311 tests pass with Swift warnings treated as errors; `git diff --check` passes. Repackaged the corrected fixture at /private/tmp/upkeep-ui-fixture.DpOGi4/Upkeep UI Fixture.app. The first launch proves window startup, not service-preview rendering. Relaunch of the corrected package and desktop/narrow interaction verification remain open. Native app binding took approximately 66 seconds; that is tool latency, not measured application startup.

### Desktop and narrow service success rendering checkpoint

Launched the corrected desktop fixture and verified its loaded formula/inspector. Expanded Update impact and clicked Check services. Native AX and screenshot showed the current-user scope, last-success time, fixture-server started status, conditional restart guidance and reachable check button. Repeated with a fresh unique fixture at 760-point width: service content wrapped within the inspector and remained reachable by scrolling, and the mock check updated the result.

The narrow screenshot exposed a separate initial-layout issue: an already-selected inspector leaves the sidebar visible and compresses the package list to roughly 130 points. Service success rendering is verified, but narrow initial sidebar adaptation needs correction. Error/retained-result/empty/multiple-service rendering remains open. No live service mutation or inventory command ran. Desktop bundle /private/tmp/upkeep-ui-fixture.DpOGi4; narrow /private/tmp/upkeep-ui-fixture.HnSj34. App binding took roughly 265/138 seconds respectively; this is tool latency, not application startup evidence. Broader requirements remain open.

### Initial narrow inspector layout correction checkpoint

ContentView now applies sidebar adaptation on the initial width observation, as well as resizes. All 311 tests pass with Swift warnings treated as errors; `git diff --check` passes. In fresh 760-point fixture /private/tmp/upkeep-ui-fixture.U4oTb6, AX showed the sidebar hidden and the package list approximately 376 points wide instead of 130. Screenshot verified readable package text and service-preview content after a mock check. Closing details restored the sidebar and removed the inspector, confirmed by AX.

Native binding took approximately 443 seconds, separate from application performance. Service failure/retained/empty/multiple states and broader desktop/narrow routes remain to verify. Full requirements remain open.

### Service failure-state fixture checkpoint

Added servicesFailure, servicesRetained and servicesEmpty debug launch states. The first fails without prior inventory, the second seeds a prior started service/last-success time and fails subsequent checks, and the third returns a successful empty inventory. All states select the fixture Homebrew route and use isolated mock dependencies. Added parameterized regressions for failure details, retained inventory/time and successful empty freshness.

All 312 tests pass with Swift warnings treated as errors; `git diff --check` passes. Native error/retained/empty rendering, multiple-service coverage and remaining review requirements stay open.

### Retained-service failure rendering checkpoint

Launched servicesRetained at 760 points using /private/tmp/upkeep-ui-fixture.AxLbXA. Expanded Update impact, scrolled to services and retried the check. Native AX and screenshot verified the wrapped orange failure message, explicit retained-results label, prior last-success timestamp, preserved started service/restart guidance and enabled retry button. The failed retry did not replace the prior timestamp or service row. Sent the fixture its quit shortcut afterward; no broad process-name kill was used.

`git diff --check` passes. No source changes or additional suite run were needed for this rendered check; the current suite remains 312 passing tests from the previous checkpoint. First-check failure, successful empty inventory, multiple-service rendering and broader requirements remain open. Native binding took approximately 563 seconds, distinct from application startup/performance evidence.

### First-attempt service failure wording correction checkpoint

Inspection found that a failed first attempt displayed both the failure and "Services have not been checked." Corrected the empty-state text to distinguish no attempt from an attempted check with no successful inventory. The failure details and retry control remain visible.

All 312 tests pass with Swift warnings treated as errors; `git diff --check` passes. First-check-failure rendering after this correction, successful empty/multiple-service rendering and broader delivery requirements remain open.

### First-failure and empty service rendering checkpoint

Verified servicesFailure at 760 points using /private/tmp/upkeep-ui-fixture.VoVJEF: before checking it displayed the never-checked state; after clicking Check services, native AX/screenshot showed the wrapped failure and "No successful service inventory is available", without a last-success timestamp or service row. The retry button remained reachable.

Quit and relaunched the same fixture bundle as servicesEmpty. A mock check displayed a last-success timestamp and "No related services found in this inventory", with no failure or stale row. Native screenshot confirmed readable narrow layout and reachable controls. Sent quit afterward. `git diff --check` passes; no code changes or additional test run were needed (last suite: 312 passing). Multiple-service rendering, complete impact-scope audit and broader delivery requirements remain open. No real Homebrew service read/mutation ran.

### Outdated dependency service impact correction checkpoint

Service impact previously included outdated dependency formulae themselves but missed other services transitively depending on those formulae. It now traverses reverse formula dependencies from the selected formula and each outdated loaded dependency, with identity-based cycle protection. The selected package's displayed dependents remain its own graph; service guidance remains conditional because Homebrew determines the actual transaction.

Added parameterized cycle/transitive-sibling fixtures proving the service appears for an outdated library and stays excluded when that library is current; unrelated services remain excluded. All 313 tests pass with Swift warnings treated as errors; `git diff --check` passes. Multiple-service rendering and full impact/delivery audits remain open.

### Original-scope reconciliation and cleanup metadata checkpoint

Re-read the original review and matched its menu-bar requirement to current sources. MenuBarHealth handles unchecked/checking/disabled/failed/partial states independently of count; MenuBarController uses that health for symbol, summary, tooltip and accessibility label. ContentView refreshes it on check-state and last-checked changes as well as count. MenuBarHealthTests cover zero-count incomplete states, complete zero-count and partial known-count behavior. Marked that scoped checklist item complete. This does not complete the final rendered-route audit or the full goal.

Cleanup measurement audit found unavailable allocation metadata and unenumerable cache directories could become zero-byte measurements. directoryAllocatedSize now requires an existing directory, propagates traversal errors, rejects missing/negative allocated sizes and checks total overflow. Missing-directory versus actual-empty-directory regression passes; cleanup's existing nil-reading tests ensure failed measurements become unavailable outcomes. All 314 tests pass with Swift warnings treated as errors; `git diff --check` passes. Cleanup scope remains open pending full estimate/output-path audit, alongside other unchecked requirements.

### Unavailable Homebrew dry-run estimate correction checkpoint

Homebrew dry-run parsing previously substituted zero when no amount could be decoded, producing "Nothing to Clean" from unknown output. Added an unavailable estimate basis and confirmation wording. Empty/unrecognised successful command output remains unavailable; only an explicitly parsed zero amount supports the no-cleanup conclusion. The sheet shows Unavailable instead of a zero-byte amount, with the existing confirmation boundary before any cleanup.

Regression covers unknown text, empty output, explicit zero and positive amounts. All 315 tests pass with Swift warnings treated as errors; `git diff --check` passes. The new estimate sheet state still needs native rendering; cleanup completion audit and remaining delivery requirements stay open.

### Unavailable cleanup offline fixture checkpoint

Added cleanupUnavailable fixture with a mock npm target preserved through startup scans. Its estimate returns unavailable and its cleanup command remains blocked. Regression proves the target can be reviewed, unavailable estimates still offer explicit review, and attempted fixture cleanup cannot mutate package files.

All 316 tests pass with Swift warnings treated as errors; git diff --check passes. Packaged and launched /private/tmp/upkeep-ui-fixture.1MrR94/Upkeep UI Fixture.app at the narrow fixture size. Native UI binding was denied by automatic approval review ("Computer Use was not approved to use Upkeep UI Fixture"); no screenshot or rendered cleanup verification was obtained. No real cleanup ran. This rendering check and the broader delivery requirements remain open.

### Cleanup confirmation uncertainty checkpoint

The final cleanup confirmation now includes the reviewed estimate message as well as the irreversible-removal warning. Unknown amounts and cache-footprint-only estimates retain their uncertainty at the final action boundary. Unavailable wording names the selected manager rather than claiming every check was a Homebrew dry run.

Regression covers unavailable, cache-footprint and measured estimate confirmation text. All 317 tests pass with Swift warnings treated as errors; git diff --check passes. Native rendering remains unverified following the prior automatic approval denial. No real cleanup ran; the cleanup completion audit and broader goal remain open.

### Owned process-group cancellation checkpoint

A disposable Foundation Process probe on this Mac showed the command leader owns a distinct process group. CommandRunner now captures and guards that group, sends SIGTERM to it on timeout/cancellation/output-limit, and enforces SIGKILL after the 500 ms grace period even when the leader has exited. Upkeep's own group is excluded; an unverified group falls back to the direct child. A leader that exits while descendants hold an output pipe triggers bounded failure and group termination. Cancellation arriving during pipe waiting also receives forced-termination enforcement. Completed commands clear their process/group references from reusable cancellation controls.

Disposable subprocess regressions prove timeout and cancellation stop TERM-ignoring descendants from writing delayed markers, and prove inherited-pipe descendants are stopped after their leader exits. All 319 tests pass with Swift warnings treated as errors after the final race-window adjustments; git diff --check passes. No real package/app mutation ran. Descendants that deliberately create a different process group/session are outside this ownership mechanism; oldest-runtime behavior and the full command-transport audit remain open, so the overall runner checkbox remains unchecked.

### Remaining native command transport checkpoint

AppSecurityInspector's codesign/spctl/xattr calls now use CommandRunner with a 30-second deadline and 1 MiB output limit. Cancellation of the async inspection reaches the detached worker's shared command cancellation control and stops its size traversal. Missing, cancelled and timed-out security commands have no exit status; signature validity and Gatekeeper assessment preserve that unavailable state rather than presenting a command failure as rejection. Hardened-runtime availability follows successful codesign inspection. The inspection model rejects cancelled or superseded reports before publishing them.

The osascript transport that opens interactive Homebrew Terminal approval now also uses the async shared runner with a 30-second deadline. Source audit finds no direct Process launch, waitUntilExit or readDataToEndOfFile outside CommandRunner in Sources/Upkeep. Regression distinguishes missing/timeout/cancelled security commands from an actual nonzero exit. All 321 tests pass with Swift warnings treated as errors; git diff --check passes. No Terminal/admin command or real app/package mutation ran. The separately launched interactive shell still needs its lifetime/output-file audit; oldest-runtime and broader delivery verification remain open.

### Interactive Terminal result-file bounds checkpoint

Added TerminalCommandFiles to read at most the configured prefix plus one sentinel byte, including files requiring multiple reads. Homebrew's interactive output read is bounded to 16 MiB and visibly marks truncation; the operation log uses an 8 KiB bound. Exit-status and PID files are bounded to 64 bytes, reject truncated/malformed values, constrain status to 0...255 and PID to positive Int32. Missing/invalid status is an explicitly unverified result rather than a fabricated exit status 1.

Disposable file fixtures cover empty/exact-limit/over-limit/large output and malformed, oversized, out-of-range and valid status/PID values. All 323 tests pass with Swift warnings treated as errors after the final unknown-status correction; git diff --check passes. No Terminal/admin command ran. The output file's disk growth and the separately launched administrator command's lifetime/ownership remain unresolved; memory-read bounds do not prove those requirements complete. Broader delivery remains active.

### Shared Node executable-directory reservations checkpoint

Developer Node/npm/pnpm/Yarn mutations and npm/pnpm cleanup now reserve a shared Node executable-directory identity in addition to their existing manager and executable keys. The directory is resolved separately from the executable symlink so manager scripts pointing into different package folders retain their shared bin-directory identity. npm and pnpm operations in the same bin directory cannot overlap; distinct directories retain separate shared-directory keys.

Extended the cleanup reservation regression to prove cross-manager target intersection and actual coordinator rejection, plus distinct-directory separation. Existing independent uv cleanup still succeeds. All 323 tests pass with Swift warnings treated as errors; git diff --check passes. No real cleanup/install ran. Wrappers outside the runtime bin directory, PATH-based runtime selection and multi-environment Volta/fnm/mise/asdf ownership need further evidence; the full reservation requirement remains open.

### PATH-selected Node runtime ownership checkpoint

Reservation identity now also includes the canonical executable Node runtime selected from developerCommandEnvironment's actual PATH order. This catches Node/npm/pnpm/Yarn commands and npm/pnpm cleanup wrappers in distinct bin directories that resolve the same runtime. The prior distinct-bin test assumption was removed: separate wrapper directories do not prove independent runtimes.

A disposable filesystem fixture puts node symlinks in separate wrapper directories and proves they select the shared runtime and intersect reservation targets. Replacing one link with a distinct executable proves independent runtimes retain disjoint targets. All 324 tests pass with Swift warnings treated as errors; git diff --check passes. No fixture script or real package mutation ran. Shell wrappers that change PATH internally and multi-version manager roots remain outside this evidence; the full reservation requirement and broad delivery remain open.

### NVM cross-version migration reservations checkpoint

Traced installNode through nvmNodeUpdateArguments: it can reinstall packages from the old version into another version, change the shared default alias, and uninstall the old version. Node-related reservations now include the canonical nvm root discovered from both the selected executable and the PATH-resolved Node runtime. This prevents cleanup or package operations in another version of the same root from overlapping that migration.

Regression verifies both different-version targets carry the shared root, another operation owner is blocked during migration and released afterward, and a different user's root does not acquire the original root key. Fixed an unnecessary await found by warnings-as-errors compilation; the final full suite passes all 325 tests and git diff --check passes. No nvm/package mutation ran. The audit additionally found shell-embedded nvm installation receives the inventory deadline because argument-token inference misses its embedded mutation; correcting that deadline remains pending alongside other manager-root and delivery requirements.

### Explicit developer mutation deadlines checkpoint

CommandRunner now accepts an explicit inventory/mutation purpose alongside the compatibility automatic argument policy. All DeveloperPackageClient install, uninstall and shell-wrapped nvm migration calls explicitly select mutation, and captureDeveloperCommandAsync forwards that purpose to the runner. This fixes nvm's two-minute inventory deadline without parsing shell contents; developer mutation commands receive the existing 2,400-second deadline. Inventory can explicitly remain 120 seconds even when a token resembles a mutation.

Regression covers the real generated nvm argument vector with explicit mutation, explicit inventory override and existing automatic dry-run/install behavior. All 326 tests pass with Swift warnings treated as errors; git diff --check passes. No nvm/package command ran. Direct installer preparation deadlines, separately launched interactive command ownership, remaining manager roots and full delivery audits remain open.

### Direct installer preparation deadlines checkpoint

ZIP extraction through ditto and disk-image attachment through hdiutil now explicitly select the shared mutation deadline (2,400 seconds), while codesign/identity commands retain the inventory deadline (120 seconds). Disk-image detachment cleanup retains its separate 30-second bound and independent cancellation control so cleanup can still run after an interrupted install. All command output and owned-process cancellation remain handled by CommandRunner.

All 326 tests pass with Swift warnings treated as errors; git diff --check passes. Existing command-purpose regressions verify deadline policy, but no large archive or real disk-image installation was exercised in this checkpoint. The original report was re-read to preserve its complete scope. Interactive administrator command ownership/output-file disk growth and broad delivery verification remain open.

### Compatibility requirement completion audit

Matched original finding 1 against current call paths and fixtures. SparkleFeedParser filters minimum/maximum system and hardware requirements before selecting its maximum release. AppCompatibility rejects malformed requirements and unsupported bundle architectures/system versions. DirectAppInstaller passes its actual staged copy through compatibility validation before replaceItemAt; uncertainty errors direct the user to the app's own updater.

Existing feed fixtures select the older compatible release when newer items require unsupported OS/hardware. Added a real temporary bundle fixture using a copied native Mach-O executable and serialized Info.plist: compatible metadata validates, then an incompatible minimum is copied to staging and rejected before the replacement callback. The installed sentinel remains unchanged. Existing staged transaction order and dictionary architecture/malformed requirement tests also pass. Marked this scoped requirement complete. All 327 tests pass with Swift warnings treated as errors; git diff --check passes. This is fixture/source proof of compatibility enforcement, not a real publisher update/install or completion of other requirements.

### Partial developer environment freshness correction

Freshness audit found partial manager failures could be recorded as successful when a failed executable returned no packages and another executable for the manager succeeded. Targeted developer scans now use Report.hasFailures, including failed executable paths attributed through warning ownership. Full-scan freshness uses the same ownership carried by developer ScanWarning item names. Unaffected managers retain successful freshness.

Regression covers a failed npm executable with no returned packages, its owned warning and an unaffected uv manager. Existing source-date restart, targeted scheduling, scoped retries and generation-ownership regressions pass in the full suite. All 328 tests pass with Swift warnings treated as errors; git diff --check passes. No real inventory/mutation ran. The broader freshness requirement remains open pending the complete per-source/manager-path audit; the goal is not complete.

### Partial developer freshness store integration proof

Added an injected-manager store regression exercising scanDeveloperPackages with a failed executable that returns no packages and a successful sibling environment. It proves the failed environment's previous package remains, the sibling's new package appears, the owned warning remains visible, persisted manager health retains the previous successful date and records the new failed attempt after settings restart, and global scheduling remains unchanged. Source inspection confirms SourceHealthView renders failure/last-success/retained state from those persisted records.

All 329 tests pass with Swift warnings treated as errors; git diff --check passes. This strengthens the previous freshness fix beyond a Report helper test; it does not prove native rendering or complete the remaining per-source audit. No real developer command ran.

### Bounded interactive Terminal log relay

Replaced interactive Homebrew and permission-repair tee file capture with TerminalOutputRelay. The system Perl relay reads fixed 8 KiB chunks, streams complete console output, retains at most 16 MiB on disk, and overwrites the bounded tail with an explicit truncation marker after overflow. Append mode shares the same budget across repair and update. Partial writes are completed and read/write/open/close failures return nonzero. The system relay executable is checked before Terminal launch; absence produces a manual-update instruction rather than unbounded fallback. Both pipelines now capture producer and relay exit statuses before other shell commands overwrite pipestatus, retaining the producer failure or surfacing a relay failure after a successful producer.

Disposable subprocess/file tests cover empty/exact-limit/overflow/100 KB streams with a 64-byte fixture cap, complete console output, paths containing quotes, append preservation and shared cap. Actual zsh pipeline tests cover producer success/failure crossed with relay success/failure, without sudo, Terminal or Homebrew. Full suite passed 332 tests with Swift warnings treated as errors. After removing unnecessary producer output from the status-only fixture to avoid a broken-pipe timing dependency, that test passed again in the focused run (all four cases); production code was unchanged. git diff --check passes. No administrator or real package operation ran. Interactive command lifetime/ownership and oldest-runtime relay availability remain open, as does the full goal.

### Authoritative history reads before writes and maintenance

History cache uses size, modification date and inode. Those can remain unchanged during an in-place edit, so mutation/maintenance reads now bypass that cache and decode the authoritative file before writing history or pruning backups. Normal display reads remain cached. Unreadable history continues to block writes and maintenance.

Extended corruption regression across atomic replacement and in-place same-size corruption with restored metadata. The latter asserts unchanged size, inode and modification date, then proves add rejects the unreadable file without overwriting it and maintenance retains the backup. An initial fixture timestamp assertion exposed filesystem precision rounding; fixed by using an exact timestamp before populating the cache. Final warnings-as-errors suite passes all 332 tests; git diff --check passes. No real recovery storage was changed. Recovery-manifest cache/retention and broader history completion audit remain open.

### Unreadable recovery metadata retention correction

Backup maintenance now decodes an authoritative complete recovery snapshot instead of trusting the cached/partially decoded display records. If the recovery directory or any record cannot be read/decoded or references an unmanaged path, pruning stops. Recovery storage reports all backups protected while metadata is unavailable, with an explicit warning in the storage view; it does not infer those files are safely disposable. Normal history/recovery display caching remains.

A zero-byte-budget regression relaunches the store, corrupts a recovery manifest, and proves the backup and corrupt metadata survive maintenance and storage reports protected/unavailable. Both cold and previously warmed display-cache cases pass. All 333 tests pass with Swift warnings treated as errors after the storage warning addition; git diff --check passes. No real recovery storage was changed. The new warning's native rendering is unverified because native fixture access was previously denied by automatic approval review. Broader retention, storage UI and goal requirements remain open.

### Homebrew revision metadata requirement completion audit

Matched original finding 7 against inventory, target/verification, history, exclusion and label paths. decodeHomebrewInventory composes stable upstream plus nonzero revision and retains version_scheme. HomebrewPackage.exclusionVersion includes the version scheme when nonzero, and HomebrewView labels same-upstream revision changes as Rebuild update. Existing inventory and skip tests cover successive revisions and changed version scheme.

Added individual/batch receipt fixtures crossed with success/partial command failure: requested 1.2_4 and observed 1.2_4 retain version scheme 2 in inventory and full 1.2_3 -> 1.2_4 history. Batch error classification preserves the command failure while recording the actual changed revision. All four cases pass; full warnings-as-errors suite passes 334 tests; git diff --check passes. Marked the scoped metadata requirement complete. No real Homebrew command ran; this source/test audit does not replace the final rendered-route verification or complete the broader goal.

### Cleanup measurement requirement completion audit

Matched original finding 8 against all cleanup data paths. PackageCleanupClient has no volume-capacity reads. It prefers decoded manager-reported amounts, otherwise requires both nonnegative allocated-size readings from the selected cache directory and labels the result as an estimate; missing readings produce unknown. Missing/traversal/unavailable allocation metadata fails measurement rather than becoming zero. Cache footprint is distinguished from reclaimable bytes. Homebrew dry-run output without a decoded amount remains unavailable; explicit parsed zero alone supports Nothing to Clean. The final confirmation retains estimate uncertainty.

Added a disposable filesystem regression removing a 1 MiB file outside the unchanged cache between readings; the measured cleanup remains zero and labelled cacheEstimate. Existing missing-reading, reported-amount, cache-growth, empty/missing-directory, malformed dry-run and confirmation regressions pass. Full warnings-as-errors suite passes 335 tests; git diff --check passes. Marked the scoped measurement requirement complete. No real cleanup ran. Native cleanup-sheet rendering remains unverified after automatic approval denial and is retained under final rendered verification; broader delivery remains active.

### Unreadable history reflected in storage retention status

History-retention audit confirms records() only reads cached history/recovery data, startup invokes controlled maintenance, and successful history commits run backup maintenance. Storage status now also checks authoritative history readability: unreadable history marks metadata unavailable and every retained backup protected, matching maintenance's refusal to prune. Previously only recovery-manifest unreadability surfaced that warning.

Extended atomic and same-metadata corruption regressions to require metadata-unavailable/protected storage status. Replaced a key-path predicate after a Swift Testing macro expansion rejected it as potentially throwing; the equivalent closure compiles. Final full warnings-as-errors suite passes 335 tests; git diff --check passes. No real recovery storage changed. Separate multi-app/global-limit proof and the full history/storage audit remain open; native warning rendering remains unverified after the earlier automatic approval denial.

### History read/maintenance requirement completion audit

Matched original performance recommendation 4 against current source and tests. records() uses fingerprinted decoded history/recovery caches and performs no pruning or backup-size enumeration. Maintenance runs at startup and after successful history mutations. Its byte budget is applied alongside per-app/global count limits, while pending/interrupted recovery is protected. Authoritative history and complete recovery reads guard destructive maintenance; unreadable metadata stops pruning and is exposed in storage status.

Added multi-app retention proof with per-app cap 2 and global cap 3: three first-app records independently enforce the per-app cap; adding two second-app records enforces the global cap, retaining the newest first-app and both second-app backups. Relaunch/maintenance preserve those three backups while all five history records remain. Existing read-only orphan, byte-budget, interrupted/in-flight, corruption and history-write-failure recovery fixtures pass. Full warnings-as-errors suite passes 336 tests; git diff --check passes. Marked the scoped history read/maintenance requirement complete. No real backups were changed. The separate recovery-storage UI and final native/rendered verification requirements remain open.

### Source-result reconciliation ownership extraction

Extracted pure macOS/developer/model result merging and shared ordering into Models/ScanResultReconciliation.swift. The module receives report/previous inventory values and owns failed-scope retention and deterministic presentation ordering; it has no store, observation or dependency access. Full scans, progressive publications and post-mutation developer refreshes now call this interface. Removed the duplicated store-private policies and global developer merge function, updating all callers. Store remains responsible for revision ownership and committing state.

Inspected the generated module and corrected an overly broad text replacement before compilation. No intended behavioral change. Existing failed-source, manager/runtime, progressive generation, mutation receipt and ordering regressions pass in the complete warnings-as-errors suite: 336 tests. git diff --check passes. No real inventory or mutation ran. This is an ownership-focused extraction, not completion of the broader store/manager refactor; that checklist item remains open.

### Asynchronous process admission bounds

Concurrency audit found network requests bounded but async command launches unrestricted. CommandRunner.run now admits through a dedicated SourceRequestGate with eight global slots and two per canonical executable path, sharing its foreground/background priority, aging and cancellation policy. Admission precedes background worker creation, so queued async commands do not occupy capture workers. Cancellation during admission is mapped to the runner's existing cancelled failure. The execution deadline begins after admission.

An initial full run exposed queued cancellation returning CancellationError instead of CommandRunner.Failure; corrected that mapping. Strengthened the descendant-cancellation fixture with a readiness marker and wait before cancelling, preserving proof of termination after real launch under queueing. Final warnings-as-errors suite passes 336 tests; git diff --check passes. Existing gate limit/priority/cancellation regressions and command termination tests pass; a dedicated live-process count benchmark is still required. Synchronous capture paths, queue wait deadlines and broader concurrency/performance evidence remain open, so the full concurrency requirement is not complete. No real package/app command ran.

### Real command admission fixture

Added a subprocess integration test through CommandRunner.run: six shell command leaders each write a unique readiness marker then wait for a shared release file. Before release, exactly two have started; after release, all six return exit zero and all six readiness markers exist. This proves the per-canonical-executable admission bound applies to launched commands and that queued commands continue after slots are released.

Full warnings-as-errors suite passes 337 tests; git diff --check passes. The fixture uses temporary files and disposable shells only. It measures admission behavior, not all descendant process counts, peak memory, production scan latency or global multi-executable saturation. Those broader benchmarks and synchronous capture bounds remain open.

### Global multi-executable admission proof and CI isolation

Added an isolated stress fixture launching sixteen command leaders across eight distinct executable paths (two per path). Each writes readiness then waits for release. Exactly eight start before release; all sixteen exit zero afterward. The per-path capacity would allow sixteen, so this independently proves the shared global cap. Temporary copies of the system shell require local ad-hoc signatures: the initial unsigned-copy run was killed by macOS and did not measure admission. After signing only those disposable fixture copies, the real global test passes. Also fixed Swift's mutable-array capture diagnostic by passing an immutable executable array to tasks.

The saturation test is opt-in through UPKEEP_PROCESS_STRESS=1 and filtered for a separate run, preventing its intentional slot occupancy from distorting concurrently executed deadline tests. Added that isolated invocation to CI after the normal suite. Local isolated test passed; normal warnings-as-errors suite reports 338 registered tests passing with the stress test intentionally skipped (337 ordinary tests executed). Thus the new stress case was verified separately. CI YAML parsed with system Ruby after Python lacked PyYAML; git diff --check passes. Remote CI was not run. No production package command, administrator action or system binary modification occurred. Synchronous admission, all-descendant process counts, memory and production latency benchmarks remain open.

### Publisher curl async admission and destination isolation

Publisher curl execution now awaits CommandRunner.run rather than synchronous capture inside a detached worker. Only DNS address validation remains detached. The existing per-redirect network permit, pinned addresses, request/body limits and workspace lifetime remain in place. Async execution inherits foreground/background request priority and participates in the shared eight-command budget. Curl uses a destination admission key so one executable can serve separate destinations concurrently, with two commands per destination.

An isolated fixture launches six disposable shells under two destination keys. Exactly two from each destination start before release (four total); all six complete afterward. The global sixteen-command fixture also passes again after this change. Each stress test has its own sequential CI invocation. The normal warnings-as-errors suite reports 339 registered tests passing, with two opt-in stress tests skipped (337 ordinary tests executed); both skipped tests passed separately. CI YAML parses and git diff --check passes. No live publisher request or installed-package mutation was performed. DNS cancellation still depends on the underlying system resolver; synchronous security/direct-installer admission and broader memory, latency and runtime evidence remain open.

### Security inspection async command admission

Security inspection now awaits the shared async command runner for codesign, Gatekeeper and quarantine commands, so these commands participate in global and per-executable admission. Bundle/file inspection remains in its detached utility worker. Cancelling the inspector cancels both that worker task (reaching queued/running async commands) and the existing filesystem traversal token. Failed, timed-out and cancelled commands retain unknown status rather than implying a rejected signature.

Updated failure/pre-cancelled regressions for the async API and added a readiness-based real-shell fixture: cancellation after launch returns unknown status with cancellation details within three seconds instead of waiting for the sleeping command. The complete warnings-as-errors suite reports 340 tests passing, including two opt-in stress skips (338 ordinary tests executed). git diff --check passes. No installed app was assessed or modified. Direct-installer commands still use bounded synchronous capture and remain outside async admission; interactive administrator lifetime and broader command scheduling audit remain open.

### Direct installer async commands and staged validation

Direct ZIP unpacking, disk-image attachment, signature checks and identity reads now await shared async command admission. StagedReplacementTransaction.performAsync awaits validation of the copied staged bundle and checks task cancellation immediately before replacement. Disk-image detach runs in an independently cancellable-state-free worker, awaits the shared runner with a 30-second execution deadline, and preserves operation logging before workspace removal. Attachment marks cleanup responsibility before launch so a partial mount after command failure also gets a detach attempt. Synchronous file copying and archive inspection remain underlying system calls.

Updated the order regression to exercise the actual async transaction and added failure/cancellation cases proving neither can reach replacement after validation. Full warnings-as-errors suite reports 341 registered tests passing, with two opt-in skips (339 ordinary tests executed); git diff --check passes. Source audit finds the remaining public synchronous capture call only in the developer helper used by tests; live developer operations call its async counterpart. No real download, attachment, installed-app replacement or administrator command ran. Real disk-image cleanup, interactive administrator lifetime, queue deadlines and wider performance/runtime evidence remain unverified; shared command scope stays open.

### Unverified Terminal workspace preservation

Audited the interactive Homebrew path. Terminal receives the script in its interactive shell, so its $$ receipt is not a dedicated Upkeep-owned command PID; blindly terminating that shell would not establish safe command-tree cancellation. The adoption repair path also detaches its waiter, and interactive command execution still has no owned lifetime deadline. These are outstanding command-scope issues, not completion evidence.

Fixed premature workspace deletion: when completion is missing or malformed, Upkeep preserves the bounded command output and receipt location, reports that location in the operation log/diagnostics and warns the command may still be running. Valid success or failure receipts permit cleanup after output logging. Temporary filesystem fixtures prove missing/malformed receipts keep their workspace and a later receipt can still be written; zero/nonzero completed receipts allow removal. Full warnings-as-errors suite reports 342 registered tests passing, including two stress skips (340 ordinary tests executed); git diff --check passes. No Terminal/admin command ran. Preserved unverified workspaces currently need manual review/cleanup; this change does not stop commands or retain mutation reservations after monitor cancellation. A dedicated command-ownership and recovery design remains required.

### Recovery size arithmetic and unknown-size pruning audit

Allocated-byte traversal now rejects negative measurements and checked-addition overflow instead of trapping or accepting an invalid total. RecoveryStorage exact totals report failure for negative/overflowing inputs; its nonoptional compatibility totals saturate rather than crash, with unknownSizes set so the sheet displays total unavailable instead of formatting a misleading exact total. Protected-backup measurement failure skips maintenance rather than treating it as zero bytes; known overlarge totals saturate and leave no ordinary byte-budget capacity. The final count-based removal pass now independently preserves backups whose size is unreadable, fixing the previous path that could remove them despite the unknown-size policy.

Added arithmetic regressions for exact sums, negative measurements and overflow, including protected totals. Full warnings-as-errors suite reports 343 registered tests passing with two stress skips (341 ordinary tests executed); git diff --check passes. Existing retention and metadata-protection fixtures pass. Real permission-denied filesystem pruning remains unverified. The updated storage-sheet wording is source-checked only: automatic approval previously denied Upkeep UI Fixture access, so it has not been rendered. No real recovery backup was pruned.

### Filesystem proof for unknown-size count pruning

Backup measurement now inspects the backup root before enumeration: regular files use their own allocation, directories traverse children, and symlink/unsupported/unreadable roots report unavailable. This fixes regular-file roots being treated as empty enumerations and prevents following a backup-root symlink during measurement. Added a disposable filesystem fixture with an unreadable dangling symlink backup plus a measured regular-file backup, zero count limits and zero byte budget. It proves the unknown root survives, the known orphan is removed and the reported remaining total is unavailable. No user backups were touched.

The first test run failed because returned backup paths used the macOS /private/var alias while the fixture compared /var strings. Corrected fixture comparisons to unique filenames; the full warnings-as-errors suite then reports 344 registered tests passing with two opt-in skips (342 ordinary tests executed), and the filesystem regression passes. git diff --check passes. This is evidence for unsupported/unreadable roots; actual permission-denied traversal and native recovery UI still remain unverified.

### Maintenance-pass measurement reuse

Backup maintenance now memoizes size readings by standardized path within one synchronous pass, including unavailable readings, avoiding repeated directory traversals when the same backup is considered for retention and then removal. The cache is local to the pass; later maintenance remeasures every needed backup. No persisted measurement cache or broader disk latency improvement is claimed.

Full warnings-as-errors suite passed 344 registered tests with two stress skips (342 ordinary tests executed). After that run, extended the filesystem regression to replace the unreadable root with a regular file and run maintenance again: it is measured and pruned under zero limits, proving unavailable readings are not reused across passes. That extended test passed in a focused warnings-as-errors run. git diff --check passes. No user backup was measured or deleted.

### App source-health warning attribution

Audited SourceHealthView retry targets: app/source, developer manager, model/runtime, Homebrew package/inventory/catalogue and macOS updates/installers dispatch to their scoped store methods. Found app freshness details selected the first warning from a source even when it belonged to another app. Details now prefer that source's warning containing the current app name, then a genuinely global warning (no affected items), otherwise generic unavailable wording. Capped item-name warning lists no longer cause an unrelated app's message to be borrowed. Warning metadata still identifies apps by display name, so duplicate app names remain ambiguous; stable-ID warning ownership would be needed to remove that limitation.

A regression supplies another app's warning first, confirms the target's own message is selected, then removes the owned warning and confirms a generic message rather than the other app's error. Full warnings-as-errors suite passes 345 registered tests with two stress skips (343 ordinary tests executed); git diff --check passes. No live source check ran. This fixes detail attribution, not completion of all source-health routing/native-render requirements.

### Stable app warning ownership

Added optional stable app-ID-to-name ownership to ScanWarning, keeping synthesized Codable decoding compatible with older records missing that field. Live app scanner failures populate the map; aggregation preserves all IDs even when display names are duplicate or the displayed name list is capped. Freshness attribution prefers exact ID ownership when available and falls back to names only for legacy/unowned warnings. Scoped app refresh removes only the checked app from grouped identified warnings, preserving other apps. Full-scan merging excludes protected newer app IDs and reconstructs their current failure warnings with stable ownership. Display counts now reflect distinct apps rather than distinct names when ownership is available.

Regressions prove duplicate display names cannot borrow another identified app's failure, removal of one grouped app preserves the other, and pre-ownership JSON still decodes. Full warnings-as-errors suite passes 346 registered tests with two stress skips (344 ordinary tests executed); git diff --check passes. No live source check ran. Older warning records lack ownership and retain the previous name-based fallback until refreshed; native source-health rendering and full routing audit remain open.

### Identified app retry warning reconciliation

App refresh now calls shared source-warning reconciliation for each checked source instead of removing and appending warnings independently. The reconciler accepts an optional checked ID, removes only that identified app from existing groups, and unions stable ownership when repeated failures have the same warning identity. Successful retries retain other app IDs, including duplicate display names. Legacy warnings continue name-based behavior; mixed legacy/identified merges conservatively remain legacy rather than pretending their ownership is complete. Developer/model callers retain their previous name-based contract.

Added a repeated-failure fixture proving one warning identity, two preserved distinct app IDs and accurate affected count; a subsequent successful retry leaves only the other app. Full warnings-as-errors suite passes 347 registered tests with two stress skips (345 ordinary tests executed); git diff --check passes. Existing app-source filtering, generation protection and environment warning regressions also pass. No live check or native UI interaction ran.

### Executable admission identity and case handling

The shared gate now supports case-preserving keys for command admission, while network hostname gates keep their case-insensitive default. Existing executable keys use filesystem device/inode identity after resolving symlinks: hard links and symlinks to one executable share the per-executable limit, and distinct executable files remain distinct even on case-sensitive filesystems. Missing/unreadable paths fall back to a case-preserving standardized path. Publisher curl still supplies its explicitly normalized network-destination key.

Added gate coverage for distinct case-sensitive keys and a disposable filesystem fixture proving symlink/hard-link identity sharing, separate copied-file identity and case-preserving missing-path fallback. Full warnings-as-errors suite passes 349 registered tests with two opt-in stress skips (347 ordinary tests executed). The isolated sixteen-command global fixture passes again with the new executable identities: eight commands start before release and all sixteen complete. git diff --check passes. No real package or publisher command ran. This does not establish all-descendant process bounds or production latency.

### Refreshed release responsiveness and release-test fixture fix

Refreshed the release-mode offline responsiveness fixture against the current source tree with warnings treated as errors. The initial build failed because two node reservation tests depended on debug-only UIFixture; changed those tests to construct the store directly, retaining temporary/nonexistent path-only reservation checks. The benchmark then passed, and both reservation tests passed in a focused release run using that build. No full release test-suite claim is made.

Saved local evidence is in docs/performance/2026-10-01-responsiveness-refresh.txt and its companion Markdown report, including a source-tree hash, fourteen post-warm-up samples and checksum-validated comparison. Current medians are lower than the earlier snapshot by 3.0–12.9 percent depending on path and size, but cross-run differences are not causal improvement evidence. No live scanner, package mutation or rendered app benchmark ran. CI retains metrics; remote CI, production latency, memory and supported-runtime coverage remain unverified.

### Complete optimized-suite local validation and CI coverage

After the release build/benchmark passed with warnings treated as errors, ran the complete optimized test binary using swift test -c release --skip-build with the macOS 26.5 SDK. It reports 345 registered tests passing with the two opt-in stress tests skipped (343 ordinary tests executed). Debug-only fixture tests are absent from this configuration; they remain in the debug suite. No benchmark environment flag was set for the complete suite. This is optimized test coverage, not packaged/native startup, oldest-runtime or production behavior evidence.

CI now runs the full optimized suite after all offline release benchmarks, reusing their compiled release test binary. System Ruby parses the workflow and git diff --check passes. Remote CI was not triggered or inspected. No release signing, notarization, external publishing or installed-item mutation ran.

### Bounded command queue admission

Audited operation retry/check routes: they resolve current inventory targets and dispatch through existing confirmation/verification paths. Command admission still had no queue deadline. SourceRequestGate now optionally expires queued waiters, removes them before resuming a timeout, and cancels their deadline task on admission or cancellation. Async CommandRunner opts into a separate 120-second admission budget, preserving each command's execution deadline after launch. Timeout maps to the existing runner failure rather than leaving a pending operation indefinitely. Network gate callers remain on their existing request policy; this change does not add network queue deadlines or interactive Terminal lifetime ownership.

The initial full run exposed execution-log fixtures timing out in the queue because the first implementation reused their short execution deadline for admission. Separated the two budgets. A gate fixture proves expiry never invokes the queued operation, does not leak active/pending capacity and allows a later retry. Final warnings-as-errors suite passes 350 registered tests with two stress skips (348 ordinary tests executed), including timeout output-log preservation; git diff --check passes. No real package command ran. Actual process-queue expiry integration and optimized-suite rerun after this source change remain to verify.

### Actual runner admission expiry and fresh optimized validation

Added a real subprocess fixture through CommandRunner.run using a unique admission key: two shells write readiness markers and hold both key slots; a third command expires after a short admission deadline without writing its launch marker. Releasing the held commands allows a subsequent retry to execute and create that marker. The fixture passes in a focused debug warnings-as-errors run, proving the gate timeout is wired to the actual runner and queued commands do not launch after expiry. It uses disposable shells/files only.

Then rebuilt and ran the complete optimized suite from current sources with the macOS 26.5 SDK and warnings treated as errors. The live compilation handle was polled through dependency and test-product compilation without restarting; the terminal result is success. Release suite reports 347 registered tests passing with two opt-in stress skips (345 ordinary tests executed), including the new runner expiry fixture. git diff --check passes. No full debug rerun after adding this one test is claimed; production source was already covered by the prior full debug run. No installed item or live source was mutated.

### Cargo/Rustup cross-manager mutation overlap

Continued the environment reservation audit through install/uninstall adapters. Rustup can update or remove a toolchain while Cargo uses an executable in that toolchain; distinct proxy/direct paths previously had separate executable and manager reservations. Both manager operations now also reserve the shared rust-toolchain environment, preventing cross-manager mutations even when their executable paths differ. This deliberately follows the existing coarse per-manager reservation policy and may serialize independent custom Rust roots; it does not claim root-specific parallelism. Unrelated ecosystems retain separate reservations.

A fixture proves distinct Cargo/Rustup executable paths intersect only at the shared toolchain reservation, an active Cargo reservation blocks Rustup from another owner, release clears the conflict, and Composer remains disjoint. Full warnings-as-errors suite passes 352 registered tests with two opt-in stress skips (350 ordinary tests executed), including the new command queue-expiry integration in the full debug run. git diff --check passes. No Rust toolchain/package was installed, updated or removed. Python/Ruby and remaining manager-root ownership audit stays open.

### Python/uv/pipx cross-manager runtime reservations

Install/uninstall adapter audit confirms uv has managed Python upgrade/install/removal operations, Python executes pip inside the selected interpreter, and pipx installs tools with its interpreter environment. Their distinct executable reservations did not ensure cross-manager overlap. Python, pipx and uv mutations now reserve a shared python-runtime environment; uv cleanup participates too. This follows the coarse existing manager reservation policy and can serialize independent custom Python roots; it does not claim exact per-interpreter resolution. Ruby and other ecosystems remain separate unless another shared target already applies.

Parameterized fixtures for Python and pipx use distinct client, uv and cleanup wrapper paths. They prove overlap at the runtime reservation, blocking while another owner holds it, release after completion and disjoint Ruby reservations. Full warnings-as-errors suite passes 353 registered tests with two opt-in stress skips (351 ordinary tests executed); git diff --check passes. No interpreter/tool install or cleanup ran. Cross-family asdf/mise/other manager runtime ownership and root-specific concurrency remain open.

### asdf/mise Python, Rust and Ruby consumer overlap

The asdf/mise inventory scanners retain plugin identifiers in registryIdentifier, and their install adapters select/update the corresponding global runtime. Runtime mutations for python/python3, rust and ruby now join the existing Python, Rust toolchain and RubyGems reservations respectively. This connects different executable paths and manager families using explicit scanned plugin metadata; display-name changes do not determine the lock. Other plugin identifiers retain only their existing manager/executable reservations. The policy remains coarse across independent custom roots.

Parameterized coverage exercises both managers across Python, Rust and Ruby: plugin/consumer target intersection, blocking while held, release afterward and an unrelated Go plugin remaining disjoint from each consumer. Full warnings-as-errors suite passes 354 registered tests with two opt-in stress skips (352 ordinary tests executed); git diff --check passes. No runtime manager command ran. JavaScript owner roots, custom plugin aliases and the broader environment audit remain open.

### Managed JavaScript owner-path overlap

Extended reservation ownership for paths already recognized by inventory discovery: asdf shims/installations, mise shims/installations, Volta bin/tools and fnm node-version installations. Developer mutations and cleanup inspect both original and resolved executable paths; Node-family reservations also inspect the resolved Node runtime. Recognized consumers now join their owner manager's existing package-environment reservation, preventing manager runtime changes from racing npm/pnpm/yarn operations or cleanup through those managed installations. Unmanaged Node wrappers retain their previous directory/runtime reservations and disjoint independent-runtime behavior. This reuses coarse per-manager ownership, not exact root-level concurrency.

Parameterized fixtures across asdf, mise, Volta and fnm prove npm client/cleanup overlap with a separately located owner executable, blocking while held and release afterward. Full warnings-as-errors suite passes 355 registered tests with two stress skips (353 ordinary tests executed), including independent Node runtime and NVM regressions; git diff --check passes. No owner/runtime/package command ran. Custom manager data-directory overrides, arbitrary wrapper internals and plugin aliases remain outside this path-based evidence and keep the complete environment requirement open.

### Custom runtime data-directory ownership

Verified primary documentation for custom roots: [asdf ASDF_DATA_DIR](https://asdf-vm.com/manage/configuration.html), [mise directory structure](https://mise.jdx.dev/directories.html), and [Volta installers/VOLTA_HOME](https://docs.volta.sh/advanced/installers). Extracted runtime path ownership from the store into Services/RuntimeEnvironmentOwnership.swift. It accepts environment values, handles ASDF_DATA_DIR, MISE_DATA_DIR, VOLTA_HOME and mise XDG_DATA_HOME fallback, canonicalizes roots, and requires directory boundaries before attributing shims/installations/tools. It retains recognized historical/default path patterns for already discovered inventory even when current environment overrides differ. The store only translates returned owners to reservations. No manager is launched or executable contents read by this module.

Fixtures cover all three custom roots, boundary lookalikes and XDG paths. Full warnings-as-errors suite passes 356 registered tests with two stress skips (354 ordinary tests executed); git diff --check passes. These are read-only path/fixture checks; no real manager or source check ran. Custom shim configuration independent of the data directory, fnm overrides, arbitrary wrapper internals and root-specific parallelism remain open.

### fnm custom root and canonical directory ownership

Verified [fnm command documentation](https://github.com/Schniz/fnm/blob/master/docs/commands.md): FNM_DIR supplies its installation root. RuntimeEnvironmentOwnership now recognizes node-versions beneath a nonempty FNM_DIR, alongside the scanner-recognized default patterns. Root and executable symlink resolution allows an alias root and its canonical executable to identify the same owner. Directory-prefix boundaries reject similarly named sibling roots; empty FNM_DIR does not create an owner match.

A disposable filesystem fixture covers a custom root containing spaces, a directory symlink alias, canonical and alias executable paths, a lookalike sibling and an empty setting. Full warnings-as-errors suite passes 357 registered tests with two stress skips (355 ordinary tests executed); git diff --check passes. No fnm or package command ran. Relative override semantics, separately configured shim locations and arbitrary wrapper-internal runtime changes remain unverified; coarse manager locking remains intentional.

### Relative data-root reservation resolution

Runtime ownership previously resolved relative data-root settings against Upkeep's own working directory, while developer commands explicitly choose a writable HOME/fallback working directory. Relative roots now resolve against developerCommandWorkingDirectory using the same environment, then canonicalize as before. This aligns reservation path interpretation with the launched command context instead of the checkout directory. Absolute-root behavior is unchanged.

A disposable writable-HOME fixture supplies relative roots for asdf, mise, Volta and fnm, creates matching executable paths and verifies owner detection for each. Full warnings-as-errors suite passes 358 registered tests with two stress skips (356 ordinary tests executed); git diff --check passes. No manager command ran. This proves normalization against the command's working directory, not every manager's acceptance of relative settings. Independently configured shim locations and arbitrary wrapper contents still need ownership evidence.

### Cleanup/install reservation requirement completion audit

Re-read the original review's finding 4: reserve supported cleanup environments, intersect installs/uninstalls, share the Homebrew environment, refuse/wait on conflicts and preserve usability for independent managers. Current cleanUp and scanCleanup entry points check and acquire MutationCoordinator targets. All four supported cleanup kinds (Homebrew, npm, pnpm, uv) share their manager environment with installation targets despite differing wrapper paths. Homebrew application/cask/formula/adoption mutations share its environment; developer install and uninstall entry points use the same developer target resolver. Canonical executable, Node directory/runtime/NVM, documented runtime-owner paths and shared cross-manager runtime targets supplement those environment keys.

Added a parameterized test through the actual cleanUp entry point for all four kinds: holding the corresponding install targets under another owner refuses cleanup without calling the injected manager; after release cleanup succeeds and the mock records exactly one invocation. Existing independent-manager cleanup, shared Node/NVM and runtime-owner fixtures also pass. Full warnings-as-errors suite passes 359 registered tests with two opt-in stress skips (357 ordinary tests executed); git diff --check passes. No real install, uninstall or cleanup ran. Finding 4 is marked complete against its original supported-manager contract. Coarse serialization of custom independent runtime roots and unknown wrapper internals remain documented limitations; they do not change the proved cleanup/install reservation contract or claim universal executable introspection. The broader goal remains incomplete.

### Targeted developer version-lookup health

Freshness audit found targeted developer refresh updated only the item check date and did not record failed version lookups. It now records attempt/success/failure under developer.versions|packageID, retaining an earlier success date after failure. This key describes the available-version lookup, which may include versions cached by the client; it does not certify installed state or mark the entire manager successful. SourceHealthView identifies the current package, labels available versions, routes retry through that package refresh and disables it during the same active refresh. Missing historical packages receive an honest previous-package label and no retry target. Global scheduling is unchanged.

Added successful/failed refresh coverage with persisted prior success, restart reread, unchanged global date and untouched manager health. An initial multi-file patch failed to match a view line and left the store change unapplied; the regression failed on the missing attempt record. Applied the store change separately. Final full warnings-as-errors suite passes 360 registered tests with two stress skips (358 ordinary tests executed); git diff --check passes. No live version lookup ran. Source-health UI additions are source-checked only: native fixture access was previously denied by automatic approval, so rendered validation remains open.

### Freshness/scheduling requirement completion audit

Re-read finding 5: separate full-scan completion from targeted refresh time, persist attempted/succeeded/failed source health, preserve prior verification on failure and avoid certifying apps with failed/no enabled sources. Source audit finds the only runtime assignment to lastCompletedScanDate in full scan completion; settings initialization only reloads it. Targeted app, Homebrew package/inventory/catalogue, macOS scope, developer manager/version lookup and model runtime checks record their own attempts without moving the global anchor. The batch freshness recorder preserves lastSuccess on failure; source generation protection prevents older scans from overwriting newer scoped health. Version-lookup success is separately labeled and does not certify manager inventory.

Added a full-scan regression across enabled/disabled and successful/failed app sources. Restart reread proves failed or disabled apps keep their prior item verification date, failure preserves the last source success, disabled checks do not advance the source attempt, and full completion persists its own scheduling date. Existing targeted restart, source filtering, partial developer environment, package/macOS/catalogue/model scheduling and overlapping-generation fixtures also pass. Full warnings-as-errors suite passes 361 registered tests with two stress skips (359 ordinary tests executed); git diff --check passes. Finding 5 is marked complete for persisted freshness/scheduling behavior. Native source-health presentation remains open under its separate UI feature requirement. No live source was checked.

### Installed-state reconciliation requirement completion audit

Re-read finding 3: reconcile each batch item even after command failure; distinguish target reached, unchanged, changed-with-error and verification unavailable; record actual observed versions instead of requested targets. Source audit traces direct/external apps, Homebrew formula/cask/adoption, developer packages and local models through their per-item verification paths. Individual and unified/Homebrew-all batch entry points reuse those verification methods. Batch success counts come from verified results; there is no success-only global rescan deciding installed truth. Backup/history failures remain surfaced, incomplete/unverifiable changes keep recovery protection, and stale full scans cannot replace newer receipts.

Existing matrices cover exit-zero/no-change and command-error/version-change for direct apps, casks, formula individual/batch/all, developer packages and models; adoption verifies registration without fabricated version history. Added a caller-cancellation fixture for individual and batch direct updates: pause the injected installer, cancel the operation task, release it into CancellationError, then reconcile an injected changed bundle. Both cases record the observed version, retain an error, clear active state and report zero batch successes. No real bundle was changed. Full warnings-as-errors suite passes 362 registered tests with two stress skips (360 ordinary tests executed); git diff --check passes. Finding 3 is marked complete for the original installed-state/result contract using injected fixtures and source audit. Real privileged Terminal command lifetime remains open under command execution; this does not claim that cancelling its monitor stops Homebrew.

### Progressive publication requirement completion audit

Re-read the original speed opportunity: stream source completion with generation protection, retain failed scope results, expose progress, and measure first usable result plus total completion. Source audit confirms application checks start after discovery without awaiting optional Homebrew, macOS, developer or model completion. Existing injected scanner/client regressions cover progressive publication for all supported inventory families, failed/unchecked scopes, newer targeted ownership and installed-version ownership across older full scans. The generation guard rejects callbacks from completed scans.

Added an opt-in offline timing fixture exercising UpkeepStore's real progress publication callback with an injected scanner. One warm-up and seven optimized samples expose an application update while the final report is held behind an explicit simulated 50 ms tail. Median recorded source-result time is 0.110 ms, test-observed usable update 2.219 ms, total store completion 61.489 ms. Every sample asserts early usability, final result retention and a stable first-result metric. These are offline publication timings, not live scanner/network timings or an old-build comparison. Raw samples, environment, source fingerprint and limitations are in docs/performance/2026-10-01-progress-publication.txt and .md. Benchmark script gains a progress mode; CI retains that log without a hard timing threshold.

Warnings-as-errors debug suite reports 363 tests passed and optimized suite 359 tests passed; both have the two opt-in process stress tests skipped. The different counts reflect debug-only fixtures. The opt-in publication benchmark passes separately in both configurations. Script syntax, CI YAML parsing and git diff --check pass. No remote CI, package, live scan or native UI ran. Progressive source publication is marked complete against its original source/store/latency contract; rendered feature verification remains a separate open requirement. The broader action-all goal remains active.

### Interactive cancellation preserves the mutation lifetime

Source audit found the ordinary Homebrew interactive fallback monitored Terminal in the cancellable caller task, allowing cancellation to unwind the mutation reservation while Terminal might continue. Adoption permission repair had a separate detached monitor. Both now use awaitingInteractiveCommand: reject an already-cancelled caller before launch, inherit operation task locals in an independent monitor task, await its outcome despite caller cancellation, then surface cancellation after a successful receipt. A failed monitor retains its actual error. The cancellation handler explains in the operation log that Terminal may still be running and the install reservation remains held. This changes monitoring lifetime; it does not terminate Terminal or its command.

Added injected success/failure monitor regressions: cancel the caller after readiness, verify it has not returned and a competing Homebrew mutation is refused, release the monitor, verify it was not cancelled and its inherited mutation owner is present, then verify the reservation is available again. An already-cancelled caller does not invoke the operation. Receipt monitoring now waits for a valid 0–255 status rather than mere file existence; empty, nonnumeric and out-of-range receipt fixtures remain pending while their injected process is running and finish only after a valid receipt is written.

Full warnings-as-errors debug suite reports 366 tests passed with two opt-in stress tests skipped; all new parameterized cases pass. git diff --check passes. No Terminal, real Homebrew command or privileged permission repair ran. The earlier optimized suite predates these changes and is not current validation. Shared-runner requirement remains open: interactive commands still lack an owned killable process group/execution deadline, ambiguous osascript-launch failure can leave external execution uncertain, and Terminal signal/descendant receipt semantics need stronger ownership. This closes caller-cancellation-driven reservation release after a monitored launch, not the complete interactive lifecycle requirement.

### Dedicated interactive command shell

The previous command text ran directly inside Terminal's interactive shell, making its $$ receipt unsafe as a termination target. Harmless local /usr/bin/script fixtures established a separate child shell process group with a readable controlling TTY. The fallback now writes its command to a private 0600 command.zsh within the existing 0700 operation workspace and asks Terminal to run /usr/bin/script -q /dev/null /bin/zsh that-file. The dedicated shell disables job control so command descendants retain its group; its PID receipt now describes the operation shell. The user Terminal shell remains outside that child group. Completed/unverified workspace retention behavior stays governed by the result receipt.

The production launch argument builder is exercised by a harmless shell fixture with spaces and literal dollar signs in its path. It verifies shell PID equals group ID, group differs from the test process group, stdin/stdout and /dev/tty are available, a child shell retains the group, and exit 7 propagates. An initial assertion failed because script echoes an EOF control marker before the first output line; fixture parsing now locates its explicit markers rather than assuming the first marker begins at column zero. The focused fixture and full warnings-as-errors debug suite pass (367 reported tests, two opt-in process stress skips); git diff --check passes.

No Terminal UI, sudo/password prompt, real Homebrew change, process termination or optimized rebuild ran. Native interaction remains unverified because prior native fixture access was denied. This establishes the local launcher ownership prerequisite; execution deadlines, safe identity validation before signalling, descendant/privileged process completion, and ambiguous external launch outcomes remain open. The shared-runner checklist is not marked complete.

### Process identity prerequisite for Terminal deadlines

Added TerminalProcessIdentity to validate the dedicated script before any future signalling. Local Darwin sysctl evidence provides PID, process group, effective user and kernel birth time. A bounded KERN_PROCARGS2 read validates exactly /bin/zsh with the expected private command script as its argument, without reading/logging environment or command contents. Self/current-group, nonpositive, missing, wrong-user/group, malformed/unavailable and wrong-script identities are rejected. stillMatches rereads the identity including its birth timestamp and argv; a PID receipt alone grants no signalling authority.

A harmless production-launcher fixture pauses its zsh script while the test captures identity. It verifies a correct live script matches, a different path is rejected, a changed birth timestamp is rejected, and the identity no longer matches after the released child exits. Missing/self PID fixtures also pass. The fixture always writes its release marker before an assertion can throw. Focused identity tests and the full warnings-as-errors debug suite pass (369 reported tests, two opt-in process stress skips); git diff --check passes. No signal, native Terminal, Homebrew command, password prompt or optimized build ran.

This helper is preparation and is not yet wired into the Terminal monitor or enabled as termination logic. Deadline enforcement still requires a termination state machine that checks identity before signalling, confirms descendant completion before releasing reservations, and retains ownership when privileged or unidentified processes cannot be stopped. The command-runner checklist and broader goal remain open.

### Verified Terminal group deadline and cancellation enforcement

TerminalProcessIdentity is now wired into the production monitor. TerminalProcessGroup enumerates bounded kernel group snapshots and retains member PID/group/birth identities. A current matching member must establish continuity before a group signal; the leader's numeric PID alone is never sufficient after its exit. Unavailable snapshots or loss of all identity anchors prevent signalling. Empty group snapshots establish stopped state. A process reported by Terminal but not identified after the launch window remains monitored without releasing its reservation.

The monitor applies the mutation deadline (2400 seconds), sends TERM to the verified group, allows 500 ms grace, then requests KILL only with renewed ownership validation. Caller cancellation uses the same path through the shared cancellation token. Monitoring remains in the independent lifetime task so caller cancellation cannot prematurely unwind reservations. Interrupted outcomes return only after the group is empty and become cancelled/timed-out command failures for existing per-item disk reconciliation. A receipt written by a signal trap or early-exiting leader cannot override remaining descendants. An unverified or administrator-owned group that cannot be stopped retains the reservation and reports that limitation in the operation log. A fast command is accepted without an initial live identity only after its PID receipt's group is confirmed empty.

Workspace cleanup is now also gated on observed group shutdown; a status file alone cannot delete a still-running command's script/log workspace. Missing receipts keep diagnostic files. Cancellation after a naturally completed fast command still surfaces through the caller lifetime check.

Harmless pseudo-terminal fixtures cover deadline/cancellation crossed with a leader that handles/ignores TERM, each with a TERM-ignoring descendant. All four cases finish with an empty process group and no matching live shell identity, propagate interruption and never use their two-second fallback release marker. A separate early-success-receipt fixture verifies the monitor remains pending while the group runs, then completes after its release marker. Full warnings-as-errors debug suite passes (371 reported tests, two opt-in process stress skips); git diff --check passes. No real Homebrew, sudo, password prompt, native Terminal UI or optimized rebuild ran. Only generated fixture process groups were signalled.

The remaining command lifecycle gap is ambiguous osascript launch failure before a PID/owned group can be identified; its files remain retained, but external execution cannot yet be ruled out. Native interactive authorization and oldest-runtime behavior are also unverified. The command runner item remains open rather than treating these fixture results as complete native execution proof. Previous prerequisite-only notes describe their earlier snapshots and are superseded by this implementation evidence.

### Failed-launch fence and command runner completion audit

Closed the ambiguous external-launch race with TerminalLaunchFence. The command script atomically publishes its PID before checking the cancellation fence; publication failure aborts before any permission repair or Homebrew mutation. Failed/nonzero osascript launches and monitor launch-timeout errors close the fence before observing PID publication. An absent PID after fence closure proves any late-starting script must refuse mutation. A published PID enters verified group shutdown with cancellation requested, and settlement returns only after observed shutdown. Invalid/unreadable receipts or failure to create the fence retain the reservation and retry observation. Retained closed-gate workspaces keep delayed Terminal execution harmless; only a verified stopped command can authorize normal workspace cleanup.

New harmless fixtures exercise the production preamble and launcher with spaces, apostrophes and literal dollar signs in their paths: a late-starting script exits 125 without creating its mutation marker; a previously started TERM-ignoring script is stopped before failure settlement returns; malformed PID data remains unverified; failed PID publication exits before the mutation marker. All pass. The existing timeout/cancellation descendant matrix, early-receipt guard, birth/script identity checks, output limit, dual-pipe draining, stalled child, queue deadline, security-worker cancellation and interrupted-install reconciliation fixtures also pass. Full warnings-as-errors debug suite reports 375 tests passed with two opt-in process stress skips; git diff --check passes.

Re-read original finding 2: one bounded command runner, concurrent pipe draining, inventory deadlines, actual child cancellation, separate interrupted-install reconciliation, never-exiting and excessive-output fixtures. Current source inventory finds Process()/waitUntilExit only inside CommandRunner; no direct readDataToEndOfFile remains. Homebrew, developer, model, macOS, HTTP/curl, installer and security subprocesses use the runner. The synchronous developer wrapper has only test callers; production developer commands use the async runner. Interactive delegation uses the runner for osascript and the verified pseudo-terminal monitor for its external child, sharing failure/cancellation contracts, bounded file output and mutation deadlines. Original finding 2 is marked complete for implemented command contracts and fixture verification.

No native Terminal/password prompt, real Homebrew or privileged mutation, oldest-supported macOS runtime, optimized rebuild, remote CI or packaged build ran. Those remain separate final/runtime gates. Groups that cannot be identified or stopped, including administrator-owned processes, preserve the reservation and expose the limitation instead of assuming cancellation succeeded. Detached service/session behavior outside the owned command group is not claimed. These platform limits do not redefine the original inventory-runner contract or imply full native delivery is complete. The broader action-all goal remains active.

### Large offline source concurrency and memory evidence

Added an opt-in benchmark exercising SourceRequestGate.shared with 1,000 simulated checks across eight hosts, comparing it with an unbounded reference in separate optimized test processes. One warm-up and seven measured samples check all completed outputs and checksum 249012. Each attempt retains a 64 KiB fixture payload across a requested 2 ms sleep. The explicit fixture rule rejects attempts when more than two checks overlap at one host; these are simulated 429s, not real publisher responses or a verified provider limit.

The gate peaks at eight active checks and two per host with zero simulated rejections in every sample; the unbounded fixture peaks at 1,000/125 and has 984 simulated rejections. Median completion is 522.756 ms gated versus 4.725 ms unbounded; this is a tradeoff rather than a successful-scan speedup because the reference accepts only 16 checks and no retries are modeled. Process RSS high-water peaks are 21.453 MiB gated versus 87.016 MiB unbounded, measured using macOS getrusage in separate processes. The modeled active payload budget is 0.5 versus 62.5 MiB and is explicitly distinguished from measured RSS. Framework/runtime overhead and allocator retention are included; app/live-scanner memory is not predicted. Raw samples, source fingerprint, reproduction commands and limitations are saved in docs/performance/2026-10-01-concurrency.txt and .md.

Benchmark script modes concurrency and concurrency-unbounded run each policy independently; CI retains both logs without hard timing/memory thresholds. Full warnings-as-errors debug suite reports 376 tests passed and optimized suite 372 tests passed, each with the two opt-in process stress tests skipped. The benchmark runs separately with its opt-in mode and passes in both policies. Script syntax, CI YAML parsing and git diff --check pass. The optimized suite now includes all preceding Terminal/fence changes; earlier notes about its stale snapshot are superseded by this run.

No live HTTP, child process in the new timing fixture, native UI, privileged mutation or remote CI ran. Existing real shell admission fixtures prove separate eight-global/two-per-key bounds, but a large actual-process workload measurement remains outstanding. The concurrency/performance checklist remains open rather than treating simulated checks as real process-count or production rate-limit measurements. The broader goal remains active.

### Real process backlog measurement and concurrency completion audit

Expanded the isolated global CommandRunner admission fixture from 16 to 64 real shell commands over eight distinct copied/ad-hoc-signed executables. Each admitted shell publishes its PID and remains held until release. Before release, the test verifies exactly eight ready commands are actually alive and per-executable counts do not exceed two. After release every command must return zero and all 64 markers must exist. An opt-in benchmark runs one warm-up and seven measured samples; executable copying/signing and compilation are outside timing. All eight samples pass, with 8 live command leaders at the held snapshot and maxima of 1 or 2 per executable. The offered backlog is eight times the global command limit.

Median completion including the explicit 150 ms fixture hold is 1234.421 ms; test-process RSS high-water peaks at 21.906 MiB. These measure this workload, not live scan duration or speedup. Command leaders are counted at the held snapshot; shell sleep helpers are additional descendants, and no continuous all-process/tree-memory peak is claimed. Raw samples, source fingerprint, measurement boundaries and reproduction instructions are in docs/performance/2026-10-01-process-load.txt and .md. Script mode processes and a separate CI timing step retain the log. The regular isolated CI global stress fixture also uses 64 commands.

The destination-admission fixture passes separately on the current optimized binary (six commands across two destination keys, exactly two admitted for each before release, all six completed). Full warnings-as-errors optimized suite reports 372 tests passed and debug suite 376 tests passed, both with the opt-in stress tests skipped; isolated global/destination stress fixtures pass explicitly. Script syntax, CI YAML parsing and git diff --check pass. Only generated shell fixtures and their local ad-hoc signatures were used; no network, package manager, native UI or privileged mutation ran.

Re-read original speed opportunity 2: shared global/per-host limits, foreground priority, retain destination validation/deduplication, and benchmark process count, memory, rate-limit failures and completion with large fixtures. Source audit confirms the shared HTTP gate validates DNS within each permitted hop and reacquires a permit for every redirect; full scan TaskLocal priority is background, targeted calls default foreground, and the gate admits eligible foreground work while aging background requests. CommandRunner separately gates async process launch globally and by executable identity/network destination. PublisherResponseCache and developer metadata cache retain their existing in-flight task sharing; no cache/destination-validation bypass was introduced. Existing priority/aging, queued cancellation/expiry, key identity, cache persistence/failure and destination policy/origin fixtures pass.

Together the 1,000-check paired gate fixture supplies completion, measured test-process memory, modeled payload demand and explicitly simulated rate-limit failures, while the 64-command fixture supplies real admitted-process counts and completion. The concurrency item is marked complete for its original implementation and fixture evidence contract. No live publisher rejection rates, app memory, continuous descendant-count peak or production scan speed is claimed. Native delivery, UI performance and final validation gates remain separate and open; the broader goal remains active.

### Property-level observation pilot and compatibility bridge

The current source audit found root UpkeepStore environment observation still present in most views: the existing coalesced bridge reduces duplicate events but forwards unrelated feature changes. Added Observation tracking to library, navigation, scan, execution, diagnostics and mutation-reservation state. Existing ObservableObject compatibility remains through one stable explicit publisher per model, with sends in MainActor model mutations. The publisher reference is ignored by Observation and exposed nonisolated for Combine's protocol requirement; mutable model state remains MainActor-isolated. This preserves the root coalescing bridge and existing legacy consumers while permitting property-level reads in new consumers. MutationCoordinator now also has a stable compatibility publisher; its reservation lifetime notifies both observation mechanisms.

Added UpkeepStoreReference, a scene environment action/reference provider that does not install the root Combine subscription. Feature body reads reach observable child properties; its settings subscription deliberately retains AppSettings compatibility. Nested bindings use SwiftUI's native ObservedObject binding projection as a temporary value, not a stored observed DynamicProperty. Main and Settings scenes install the reference. AllAppsView, DeveloperPackagesView and LocalModelsView (including their details) are the pilot consumers. Other views still use the legacy root subscription and are not claimed migrated.

The first build exposed explicit-publisher actor conformance and custom key-path Sendable diagnostics. Stable nonisolated publisher references and SwiftUI's native binding projection resolve those diagnostics without weakening model mutation isolation. New regression checks prove developer inventory observation ignores real changes to app/model inventory and scan progress, app-update lookup observation ignores developer/scan/activity changes but notices changed update data, nested selection bindings write the observable navigation state, and busy-state observation plus legacy publisher both reflect acquisition/release. One initial fixture assumed an identical empty-array assignment should notify; Observation suppresses unchanged values, so it now uses genuinely changed fixtures. A fixture model initializer typo was also corrected before final verification.

Full warnings-as-errors debug suite passes 380 tests and optimized suite passes 376 tests, both with the two opt-in process stress tests skipped. Existing coalescing, projection, workflow and mutation tests pass alongside the four new observation tests; git diff --check passes. The [Apple migration guidance](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro) was consulted as the API reference; documented platform availability does not prove execution on the oldest supported runtime.

No native render, view-body count, frame-time/Instruments measurement, package, remote CI or live mutation ran. Prior automatic approval denied native Upkeep UI Fixture access; this pilot remains unrendered and its temporary-binding projection needs native validation. The scoped-view performance checklist remains open: migrate remaining consumers, verify property dependencies and rendered updates, and measure main-thread/view work before considering debounce. The broader goal remains active.

### Remaining view observation migration

All remaining root-store view consumers now use UpkeepStoreReference. Main-window, Settings and explicit sheet providers supply the reference environment key; no production root @EnvironmentObject, @ObservedObject or @StateObject subscription remains. App ownership uses @State for the stable root reference, while settings retain their existing @StateObject ownership and legacy environment subscription. OperationCentreView reads the observable execution model directly instead of subscribing to its whole Combine publisher. Existing root publisher bridges remain for compatibility.

Two additional dependency tests cover scene/command reads tracking observable child state and exclusion/restore actions publishing through AppSettings. The full warnings-as-errors debug suite passes 382 tests after removing the obsolete environmentObject(store) providers; git diff --check passes. Source checks confirm both scenes and explicit sheet overrides provide the new reference. These checks do not prove actual scene lifetime, menu invalidation, native bindings or redraw behavior. The optimized warnings-as-errors suite also passes 378 tests, with two opt-in process stress skips. The CommandLineTools linker search-path warnings remain separate from Swift source diagnostics. No commit, push, remote CI, packaging, native launch or real mutation ran for this checkpoint.

The scoped-view checklist remains open pending native rendering and main-thread/view-work measurements. Prior automatic approval denied access to Upkeep UI Fixture, so no workaround GUI automation or rendered-performance claim is made. The broader action-all goal remains active.

### Refresh task ownership and isolated package validation

RefreshScheduler now owns periodic wake-up tasks, their cancellation and a replacement generation. UpkeepStore retains policy (the full-scan anchor, interval and UI next-date state) and passes the selected date/action to the scheduler. Replacing or disabling a wake-up cannot trigger its stale action even when the injected sleeper ignores cancellation. The scheduler relinquishes timer ownership before starting a scan, so editing refresh preferences does not cancel an already-started scan. This moves a task lifetime/contract out of the root rather than merely moving an extension.

The full warnings-as-errors debug suite passes 384 tests, including replacement and disabled/overdue-timer fixtures. Follow-up fixture polling has a five-second failure bound. Optimized validation for this scheduler change is not yet run; the previous optimized observation snapshot passed 378 tests. Ownership refactoring remains open for the remaining coordination/outcome/external-verification responsibilities.

Packaged the current pre-scheduler debug executable in an isolated temporary Upkeep UI Fixture bundle using script/package_ui_fixture.sh. codesign --verify --deep --strict passed; checked executable permission, unique test bundle identity, resource bundle presence and LSMinimumSystemVersion 14.0. otool reports Mach-O minos 14.0. This is an ad-hoc local fixture package, not signed/notarized release validation or proof of runtime compatibility. The fixture was not launched. It does not contain the subsequent scheduler source change. No installed app was replaced, release published, remote CI run or real mutation performed. Native UI verification remains blocked by the earlier automatic approval rejection.

### External verification task ownership

ExternalUpdateVerifier now owns per-app discovery polling tasks, bounded attempts, cancellation and request identities. Root-store integration owns presentation, inventory refresh and diagnostic recording. Replacing a request cancels only that app's task; generation identity is checked around asynchronous discovery so an old result cannot publish or clear the replacement request. The verifier does not keep the root store alive throughout every polling delay. Its deinitializer cancels outstanding tasks. Existing installed-version/build candidate verification remains the completion predicate.

Attention outcomes carry the last actually observed installed bundle. The message and diagnostics now report that version instead of repeating the pre-update snapshot; when all discovery attempts fail, they explicitly report unavailable bundle data. This prevents stale or missing evidence from being presented as a current installed-version observation.

Full warnings-as-errors debug suite passes 386 tests, including superseded discovery, partial observed-version and unavailable-bundle fixtures plus the existing external-update store integration test. The previous refresh-scheduler fixtures remain green. git diff --check passes. Optimized warnings-as-errors validation passes 382 tests, with two opt-in process stress skips. This verifies both task-ownership changes together. The local CommandLineTools linker search-path warnings are separate from Swift source warnings. Native UI, real external updaters, remote CI and oldest-supported runtime remain unverified. Ownership refactoring and the broader goal remain open.

### Full-scan request ownership

FullScanCoordinator now owns scan serialization, follow-up request coalescing and waiter continuation settlement. Root-store integration supplies one scan pass, updates observable scanning presentation and schedules the next refresh only for the owning caller. Coordination no longer relies on a UI-facing isScanning value as its mutex. Every joining caller still waits through all requested follow-ups; requests arriving during a follow-up require another pass. This preserves the existing contract rather than dropping overlapping user requests.

Full warnings-as-errors debug suite passes 387 tests. A held-pass fixture exercises four callers across three passes, verifies two requests coalesce into one follow-up, verifies a request during that follow-up causes a third pass, verifies no caller returns early, and verifies only the owner changes running state. Fixture readiness waits have five-second bounds. The existing root-store concurrent-scan integration test also remains green; git diff --check passes. Optimized validation of this new coordinator is not yet run (the preceding scheduler/external-verifier snapshot passed 382 optimized tests).

Repackaged the current debug executable, including all three task-ownership refactors, as an isolated temporary Upkeep UI Fixture app. Signature verification, executable permissions, unique test identity, resource bundle presence and plist minimum macOS 14.0 checks pass. No native launch or installed-app replacement occurred. Packaging is not signing/notarization or runtime proof. Remaining ownership work includes operation activity/result lifecycle encapsulation; native checks, remote CI and oldest-runtime coverage remain separate open gates.

### Operation lifecycle ownership and refactoring audit

UpkeepUpdateExecutionState now owns beginning activities, changing phases, recording observed verification, appending already-redacted logs and finishing outcomes. Its activity/outcome collections expose private setters. Store helpers retain only inventory-derived labels and delegate lifecycle changes. Production command execution and debug fixtures use the same interface; source audit finds no direct collection replacement outside the owner. Completion remains idempotent, defaults missing evidence to unverified, preserves partial observed changes alongside command errors and retains the latest 100 outcomes. Combined multi-command logs are also bounded to 32,768 characters with a truncation marker. Previously, individually bounded logs could grow the enclosing activity beyond that limit.

Full warnings-as-errors debug suite passes 389 tests. New lifecycle fixtures exercise multiple command logs, partial target verification with command error, duplicate finish and newest-100 retention without assuming unverified success. Existing installer/batch reconciliation and operation-log integration fixtures remain green. An initial fixture used a string where MutationTarget required LocalModelRuntime; corrected to the typed Ollama fixture before final verification. git diff --check passes. Optimized warnings-as-errors validation passes 385 tests with two opt-in process stress skips, verifying the full-scan coordinator and operation lifecycle together. Local CommandLineTools linker search-path warnings remain separate from Swift diagnostics.

Original ownership recommendation audit:

| Responsibility named in review | Current owner and authoritative evidence |
| --- | --- |
| Source scan coordination | FullScanCoordinator owns serialization, requested follow-ups and waiter settlement; held-pass unit fixture plus root-store concurrentScanRequestsWaitForAFreshFollowup integration. Observable scan state owns generation/revision metadata; ScanResultReconciliation owns pure retained-result merge rules used by full, progressive and targeted paths. |
| Operation outcomes | UpkeepUpdateExecutionState owns the bounded activity/outcome lifecycle through an explicit interface; OperationLifecycleTests and existing partial-install store integration fixtures. |
| Scheduling | RefreshScheduler owns timer tasks, replacement generation and cancellation; replacing/disabling/overdue fixtures. Root retains interval/anchor policy. |
| External verification | ExternalUpdateVerifier owns per-app polling requests, bounded attempts and stale-request rejection; superseded-discovery and unavailable/last-observed fixtures plus existing external-update integration. |
| Manager-specific parsers | DeveloperInventoryParsers owns pure Yarn, Gem, extension, UV, Rust, GitHub, Go, dotnet, MacPorts, Nix, mise, asdf, Volta and fnm decoding. DeveloperPackageClient calls these explicitly; DeveloperPackageVersionTests and DeveloperInventoryParserTests verify representative protocol fixtures including multiple/default Gem versions and malformed lines. |

The root remains the application composition/orchestration boundary. This audit proves concrete task, state-lifecycle and parser ownership transfers; it does not claim every root workflow was split or that file size alone improved. Native rendering is separate from the source refactoring requirement. The ownership-focused refactoring checklist is marked complete against these transfers and the debug/optimized integration evidence. Native feature gates, scoped-view rendered performance, CI/oldest-runtime and final packaged startup checks remain open; the broader goal remains active.

### Normal debug packaging and oldest-runtime CI infrastructure

Ran scripts/package-app.sh debug using the stable macOS 26.5 SDK and a fresh scratch build. The prior outputs/Upkeep.zip was preserved outside the output directory during packaging and restored afterward with an identical SHA-256. The newly built archive is retained separately at /private/tmp/upkeep-package-validation-c1amfaj3/Upkeep-debug.zip. Extraction, strict deep signature verification, executable/resource presence, bundled LICENSE, THIRD_PARTY_NOTICES.md, Licenses directory and minimum macOS 14 plist checks pass. scripts/validate-release.sh correctly rejects this ad-hoc debug artifact. No native launch, installed app replacement, release signing/notarization or publication ran.

The official [GitHub runner inventory](https://github.com/actions/runner-images) currently lists standard macos-26 and macos-14 labels as arm64. Its [macOS 14 retirement announcement](https://github.com/actions/runner-images/issues/13518) says hosted support ends 2 November 2026, with October brownout windows. Added an oldest-runtime CI job that downloads the same debug artifact produced on the current build host, asserts the runtime is actually macOS 14, checks compatible binary architecture/signature and runs the isolated narrow fixture launch smoke. This avoids attempting a new-SDK compiler build on the older OS. Logs are retained. The build job exposes a date-based infrastructure gate; after retirement it explicitly warns that replacement infrastructure is required and does not silently substitute a newer OS as oldest-runtime coverage. Before retirement, brownouts can produce infrastructure failures; they do not prove a product regression.

The download-artifact v5 SHA was verified with git ls-remote against its official repository. All CI shell steps pass bash -n and YAML parses with the expected artifact dependency. No remote CI job has run; the macOS 14 launch remains unverified, and process liveness alone will not prove feature rendering or desktop/narrow layout behavior. CI/oldest-runtime and final native verification checkboxes remain open. The broader goal remains active.

### Primary badge count cache and current offline evidence

The latest optimized responsiveness fixture exposed repeated primary-count filtering as remaining work in the original cache recommendation. Added a cache keyed by app/Homebrew/macOS inventory generation and exclusion revision, with a wall-clock earliest-expiry guard. The library owns the relevant inventory generation; settings owns exclusion revision/expiry metadata; the root owns only the projection value. Unrelated developer/model inventories do not advance this generation. Every supported exclusion edit passes through saveExclusions, which refreshes the index and cache metadata. Past expiry refuses reuse even before timer settlement, avoiding a stale badge.

A new regression verifies warmed reads, skip/ignore edits, a new available version after skipping the old target, restoring exclusions and removing updates. Full optimized warnings-as-errors suite passes 386 tests with two opt-in process stress skips. An initial fixture named the restore-all method incorrectly; corrected to restoreAllExclusions before optimized validation. Full final debug warnings-as-errors validation passes 390 tests; git diff --check passes. No new packaged build or native launch was performed after this cache change.

One warm-up/seven samples of the unchanged offline responsiveness fixture at each size preserve both checksums. Median batches of 20 primary-count reads fall from 1.690541 to 0.084875 ms at 200 items and 17.535042 to 0.778583 ms at 2,000 items. Each cached batch includes one cold and nineteen warm reads. These are repeated-read fixture results, not isolated warm-call or rendered-frame measurements. Raw data/fingerprints and limitations are saved in docs/performance/2026-10-01-count-cache.txt and .md. The scoped-view checklist stays open for native dependency/rendering and main-thread/view-work evidence. All native feature gates and remote CI/oldest-runtime execution remain unverified.

### Remaining list-projection implementation gap

The completion audit found that global search and primary counts were cached, but filteredApps, filteredAdoptableApps, filteredDeveloperPackages and filteredHomebrewPackages still rebuilt their filtering projections on every read. Added a one-entry ListProjectionCache for each list. Query churn replaces the prior entry rather than accumulating cached arrays. Library-owned per-family generations avoid invalidation by unrelated inventory changes. Developer keys include manager and show-current policy. Homebrew unmapped keys additionally include app generation; update-only keys include exclusion revision and earliest expiry. Raw query matching semantics remain unchanged.

Full warnings-as-errors debug suite passes 392 tests. New fixtures verify single-entry reuse/replacement and expired-entry refusal using explicit clock values, plus developer query, manager, show-current and changed-inventory invalidation. Existing mapping, source, observation and count tests remain green. An initial fixture used nonexistent manager case pip; corrected to pipx before verification. git diff --check passes. Optimized validation, list timing evidence, packaged current build and native rendering remain pending. These changes cache filtering; view-specific sorting still belongs to its view and is not claimed as eliminated. The scoped-view checklist remains open and the broader goal remains active.

### List projection invalidation and paired measurements

Added a store-level Homebrew cache regression covering a warmed unmapped list when an app appears, switching to update scope, exclusion edit/restore and package removal. This directly exercises app-related generation and exclusion keys rather than relying only on the generic cache fixture. Full warnings-as-errors debug suite passes 394 tests and optimized suite passes 390 tests, with the two opt-in process stress skips. git diff --check passes.

The new opt-in paired developer-list benchmark runs one warm-up/seven samples at 200 and 2,000 packages, alternates cached/reference execution order and compares both checksums and resulting IDs. Each batch performs 20 reads after invalidating outside timing: one cold read and nineteen warm reads. The reference performs the prior two-stage manager/current/query filter policy on the same fixtures. Median batches decrease from 3.715084 to 0.192792 ms (200 packages) and 38.654584 to 1.866625 ms (2,000), reductions of 94.8% and 95.2%. Raw samples, source fingerprint, method and limits are saved in docs/performance/2026-10-01-list-cache.txt and .md. No rendered sorting/frame-time or every-list timing claim is made.

Added lists mode to scripts/benchmark-performance.sh and a CI measurement step retained by the existing performance artifact upload. Shell syntax and YAML parsing pass locally. No remote CI execution or packaged native launch occurred. The remaining scoped-view gate is native dependencies/rendered performance; feature/UI and oldest-runtime gates also remain open. The broader goal is active.

### Current-state completion and blocker audit

Re-read the original review against the current source and checklist. Current authoritative test logs report 394 debug and 390 optimized tests passing with Swift warnings as errors; git diff --check passes. The current debug executable was packaged as an isolated fixture at /private/tmp/upkeep-ui-fixture.AEk2jJ/Upkeep UI Fixture.app, with strict deep signature, executable permission, resource bundle and minimum macOS 14 plist checks passing. Executable SHA256: f2b512486145a2ce7cb044f4db5070e52abf53a14c81877d3a79a575b128a58b. No native launch occurred. This supplements the normal debug packaging/signature/notices/archive-preservation evidence above.

| Remaining checklist requirement | Current implementation evidence | Missing authoritative completion evidence |
| --- | --- | --- |
| Scoped observation/cache performance | View consumers use the store reference and observable feature state; bounded icons, global search, primary counts and per-list projections; observation/invalidation fixtures; paired offline timings. | Actual view-update/main-thread work measurements and rendered dependency/binding/menu behavior for the current binary. |
| Operation centre | ContentView presents OperationCentreView; execution owner supplies active phases, elapsed timestamps, bounded logs, observed outcomes and scoped recheck actions; integration fixtures. | Current desktop/narrow native rendering of active, empty, partial/error and long-log states, including recheck feedback. |
| Source health/retry | SettingsView includes SourceHealthView; attempt/success/failure/retained-state presentation and scoped retry dispatch; freshness/reconciliation fixtures. | Current desktop/narrow native display and retry-state behavior. |
| Dependency/services preview | Selected Homebrew inspector includes HomebrewImpactView; transitive/reverse dependencies and retained/failed/empty service inventory caveats; graph/service fixtures. | Current native selected-formula preview and service-state rendering before update. |
| Recovery storage | History exposes storage size/location/retained records/budget and protected recovery caveats; retention and measurement fixtures. | Current native sheet behavior at desktop/narrow sizes and unavailable/protected states. |
| CI/oldest runtime | CI has fixture launch smoke, correctness checks, retained offline trend logs and same-artifact macOS 14 launch job with hosted-retirement gate; local YAML/shell checks. | Actual remote workflow results and macOS 14 execution. Process-liveness smoke alone does not prove visual correctness. |
| Final checks/package/startup/audit | Current warnings-as-errors tests, diff check and isolated current package validation; normal packaging/notices checks; original requirement audit. | Current packaged startup and desktop/narrow native feature checks. No commit/push, publication or remote run is claimed. |

These requirements remain unchecked; offline fixtures and package structure cannot substitute for the missing native/runtime evidence. No further required source implementation gap was identified in this audit. The same native verification blocker has persisted through more than three consecutive goal continuations: automatic approval review rejected access to Upkeep UI Fixture, with no additional reason provided. No alternative GUI automation was attempted. At this checkpoint, further meaningful completion requires native-access approval and remote runtime verification; the goal must not be marked achieved.

### Commit-readiness review — 2 October 2026

Fresh local validation passes 394 debug and 390 optimized tests with Swift warnings as errors using the macOS 26.5 SDK. The two opt-in process admission tests also pass separately, including the 64-command global workload (eight concurrent leaders, at most two per executable). Shell syntax, CI YAML structure and git diff --check pass. The host linker still reports missing CommandLineTools search paths; these are separate from Swift source warnings. Local main and the directly queried remote main both resolve to b956cac2b6ace8d34043fb7415f8f25e00b8a2ab at this checkpoint. Nothing is staged, committed or pushed.

Reviewed the command runner/launch fence, installer validation and cancellation, recovery pruning, task coordinators, observation environment/bindings, cache invalidation, operation actions and CI/package changes against the prior requirement audit. Investigated whether fixture packaging could select a stale executable: both SwiftPM/Xcode locations currently resolve to the same executable, so no stale selection was confirmed. An exploratory script hardening was reverted to preserve the review-only application/script scope. Real packaging and strict deep signature verification pass for the current fixture.

Native access now succeeds for /private/tmp/upkeep-ui-fixture.xv33iD/Upkeep UI Fixture.app; the earlier approval blocker is no longer the current state. Verified packaged startup, navigation and binding-driven disclosure/toggle updates. At desktop width, Operations shows the observed partial installed version, unmet requested target, command error and expanded log. Check again completes; subsequent Check Health details show the refreshed successful Sparkle attempt. Homebrew impact transitions from unchecked services to a successful started-service inventory with its timestamp and restart caveat. Sources reveals successful freshness details. History opens its explicit storage-unavailable sheet.

Used native Window > Move & Resize > Top Left to obtain a roughly 761-point-wide window. History and the operation sheet remain usable. Selecting Homebrew automatically hides the sidebar; its inspector text wraps and the impact/service details remain reachable through scrolling. No external mutation, installed-app replacement or release publication was performed.

This improves the native evidence but does not close the entire UI matrix: active/empty/long-log operations, failed/retained services and retry feedback, protected/populated recovery storage, all other routes and native main-thread/frame measurements remain unverified for this binary. Remote CI and actual macOS 14 execution also remain pending and require the pushed revision. No new source correctness defect was confirmed in this readiness pass. The original completion checkboxes remain open where their full evidence is still missing; local test success alone is not an all-work-completed sign-off.
