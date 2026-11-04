# Dependency and build review — 4 November 2026

Reviewed all declared Swift packages, transitive lockfile entries, GitHub Actions,
and the downloaded CI scanner. Upkeep now uses toolchain-bundled Swift Testing
and has no external Swift package dependencies. Homebrew and developer tools
inventoried by the app are user integrations, not repository dependencies.

## Dependency decisions

| Component | Previous | Final selection | Changelog review and required changes |
| --- | --- | --- | --- |
| [Swift Testing](https://github.com/swiftlang/swift-testing/releases/tag/swift-6.4.2-RELEASE) | Separately built 6.3.2 package | Selected toolchain's bundled framework | Reviewed 6.4.0–6.4.2 changes to issue attribution, expectation diagnostics, repetitions and events. Removed the external package in favor of the [upstream-recommended distribution](https://github.com/swiftlang/swift-testing/blob/swift-6.4.2-RELEASE/Documentation/Distributions.md), keeping macros/runtime matched to the compiler. Local toolchain: Swift 6.4.2. |
| [SwiftSyntax](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0) | Transitive 603.0.2 | No separate package build | Reviewed 604.0.0's doc-comment API and absence of listed incompatible API changes. Removing the separate Testing package also removes this dependency and its prebuilt/source macro builds. |
| [actions/checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) | 7.0.1 | Unchanged | Latest stable version at review. Patch fixes concern branch whitespace, unset escaping and unsafe-PR-check defaults; credentials remain disabled. |
| [actions/upload-artifact](https://github.com/actions/upload-artifact/releases/tag/v7.0.2) | 7.0.0 | 7.0.2, commit-pinned | Reviewed 7.0.1/7.0.2 dependency fixes and HTTP 429/Retry-After retry handling. Existing artifact inputs remain supported. |
| [actions/download-artifact](https://github.com/actions/download-artifact/releases/tag/v8.0.2) | 5.0.0 | 8.0.2, commit-pinned | Reviewed 6.0.0–8.0.2. Node 24 requires runner 2.327.1+. ESM is transparent to callers. Digest mismatches now fail by default; enforcement is retained. Single named downloads preserve the expected extraction layout, including the nested Upkeep.zip. |
| [Gitleaks](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1) | 8.30.1 | Unchanged | Latest stable at review. Reviewed Go/tooling and report changes. Existing archive checksum retained. |

Action commit IDs were checked against upstream release tags. Historical Swift
Testing/SwiftSyntax licence files are retained; THIRD_PARTY_NOTICES.md explains
the final distribution. SwiftPM removed Package.resolved when the last external
package dependency was removed.

## Default-backend fixes

The installed toolchain is Apple Swift 6.4.2 with the macOS 27.2 SDK. No full
Xcode installation was found. The normal default-backend command exposed these
project/toolchain integration issues:

1. **SwiftUI State macro plugin:** the SDK declares both the public State property
   wrapper and same-named macros, but Command Line Tools omit SwiftUIMacros.
   `UpkeepState` is a type alias to the public SwiftUI.State property wrapper.
   State declarations and explicit initializers use that name, preserving native
   storage, observation and bindings without implementing a replacement wrapper.
2. **Testing distribution:** build the tests against the framework, macro plugin
   and runtime provided by the selected compiler. Plain SwiftBuild also omitted
   the bundled Testing macro-plugin path; this was reproduced in a one-test
   package and confirmed by comparing compiler invocations. The test target now
   resolves the compiler with xcrun and declares its installed plugin/server
   paths. This honors DEVELOPER_DIR and TOOLCHAINS rather than hardcoding an SDK
   or developer directory. No separate Testing package, SwiftSyntax prebuilt
   override or manually supplied runtime library is needed.
3. **TaskLocal overload:** wrap the stored mutation operation in a closure so the
   compiler can select the current caller-context overload. A regression test
   checks owner identity across suspension/nesting and reservation release.
4. **Type inference:** split the fixed-release-version pipeline into typed
   intermediate values, preserving package scoping, range/event filters,
   deduplication and sorting while avoiding the new compiler's type-check timeout.

The earlier list separator closure also captures a precomputed offset, removing
actor-isolation warnings. No files inside the toolchain installation, global SDK
selection or backend defaults were changed. After changing
Testing distributions, `swift package clean` removes stale module products from
the previous external-package build.

## Toolchain and CI

The project uses Swift tools 6.3 or newer. CI and releases select Xcode 26.6,
listed in the [macOS 26 hosted runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
Apple lists its compiler as Swift 6.3 in the [Xcode requirements](https://developer.apple.com/xcode/system-requirements/).
Testing follows that explicitly selected toolchain rather than an independent
package version. The app's macOS 14 deployment target is unchanged.

The macOS 14 hosted-runner availability gate expired on 2 November. Upgrading
packages/actions does not restore oldest-runtime validation. Xcode 26.6 hosted
CI and macOS 14 runtime testing have not been performed locally.

## Validation

The default command and the stricter CI validation command are:

```sh
swift test
swift test --no-parallel -Xswiftc -warnings-as-errors
```

No SDK, backend, experimental-prebuilt, library-search or rpath override belongs
in either command. Final results:

- **Clean default build:** `swift package clean` followed by plain `swift test`
  passed all **441 tests**. The default backend is SwiftBuild, using the default
  macOS 27.2 SDK. An earlier non-clean plain run also passed all 441 tests.
- **Strict validation:** `swift test --no-parallel -Xswiftc -warnings-as-errors`
  passed all **441 tests**, including the new nested mutation-owner regression.
- **Opt-in process tests:** both global admission across distinct executables and
  admission across network destinations passed separately with
  `UPKEEP_PROCESS_STRESS=1`, using the default backend and no custom search paths.
- **App packaging/runtime:** plain `./scripts/package-app.sh debug` succeeded with
  the default SDK. The extracted ad-hoc signature verified; bundled notices
  matched the source. An isolated fixture copy rendered at 1180×720 and 760×553;
  selection, inspector closing, and opening/closing Operations worked. The copy
  was closed without executing a real update or cleanup. The app binary does not
  link Testing. SwiftBuild still emits warnings about two missing CLT default
  search directories; those did not prevent building, linking or testing.
- **Static/CI checks:** workflow YAML parsing, shell syntax and `git diff --check`
  passed. State changes in 14 existing files were checked to be mechanical alias
  and initializer-name replacements. CI now includes a run without compiler
  overrides and a manual trigger for branch verification. Hosted workflow
  results are separate from these local checks.

Process-admission stress cases remain separate, as in CI, because saturating
their shared gates would distort other process deadline fixtures.

Hosted Actions execution, commits, pushes and release publication are separate
from local validation.

## Hosted CI follow-up

The [first branch CI run](https://github.com/dyd4dsh7/UpKeep/actions/runs/41749080605)
passed debug tests, process isolation, packaging, signature checks and the narrow
launch smoke test. Its release build exposed CVE tests referring to the app's
debug-only UIFixture. Those tests now use an offline CVEStoreFixture owned by
the test target in both configurations; the app fixture remains debug-only.

Running the enabled release benchmark also found an outdated expected update
count. Its fixture now counts non-excluded app offers, all Homebrew packages
(including dependencies), and developer offers, consistent with the current
unified update count. All benchmark assertions remain enabled.

Local follow-up checks passed all eight release benchmark modes, all 437
optimized tests, and 34 targeted debug CVE tests with compiler warnings treated
as errors. The four UI-fixture tests are intentionally debug-only. The remaining
benchmark modes reused the compiled release test binary to avoid repeated builds;
the CI workflow continues to run its complete benchmark commands.
