# Contributing to Upkeep

Bug reports, documentation fixes, and focused pull requests are welcome. For a
large feature or change to update behaviour, open an issue before implementation
so its scope and safety expectations can be agreed.

## Build and run

Use macOS with Xcode 26.6 or newer (Swift 6.3+), or matching Apple Command Line
Tools. The SDK must be macOS 26 or newer; the deployment target remains macOS 14.
CI selects Xcode 26.6 explicitly. Homebrew and other package managers are optional
integrations, not build dependencies. You do not need signing credentials to
contribute.

Tests use the Swift Testing bundled with the selected toolchain. A separate
`swift-testing` package, backend override and custom linker paths are unnecessary.
The app selects SwiftUI's native State property wrapper through `UpkeepState`,
so Command Line Tools do not need the macOS 27 SwiftUIMacros plugin.

```sh
git clone https://github.com/dyd4dsh7/UpKeep.git
cd UpKeep
swift test -Xswiftc -warnings-as-errors
./script/build_and_run.sh
```

The run script stops a running Upkeep process, packages a debug app, and launches
`dist/Upkeep.app`. It uses the normal app preferences and local data. Only confirm
updates, restores, package adoption, or cleanup when you intend those changes.
Debug packages are ad-hoc signed and are not official distribution builds.

## Where to work

- `Sources/Upkeep/Views`: SwiftUI windows, lists, settings, and inspectors.
- `Sources/Upkeep/Services`: discovery, publisher requests, package commands,
  installation, diagnostics, and backups.
- `Sources/Upkeep/Stores` and `UpkeepStore.swift`: state and operation coordination.
- `Tests/UpkeepTests`: Swift Testing fixtures and regression tests.
- `scripts`: packaging, release validation, and performance measurements.

## Pull requests

1. Create a branch from current `main`; keep unrelated changes separate.
2. Explain the problem, resulting behaviour, and how you verified it.
3. Run the test command above. For update/install changes, add a regression test
   using temporary directories and injected dependencies, not real installed apps.
4. For UI changes, inspect the packaged app at a normal window size and at a
   narrow supported width. Check both appearances when changing colours/artwork.
5. Update documentation and the Unreleased changelog where behaviour changes.

Do not weaken publisher validation, archive checks, app identity checks, mutation
coordination, or confirmation steps to make a test or update succeed. Never put
credentials, personal diagnostics, signed certificates, or private fixtures in a
PR. Report vulnerabilities through [SECURITY.md](SECURITY.md).

By submitting a contribution, you confirm you have the right to contribute it
and agree it can be distributed under the project's MIT licence. Retain all
third-party licence notices and provide provenance for new dependencies or assets.
No separate contributor licence agreement is required.

Please keep discussion respectful, specific, and relevant. The project is
maintained on a best-effort basis; there is no guaranteed support response time.
