# Contributing to Upkeep

Bug reports, documentation fixes, and focused pull requests are welcome. For a
large feature or change to update behaviour, open an issue before implementation
so its scope and safety expectations can be agreed.

## Build and run

Use macOS with Xcode 26.6 or newer (Swift 6.3+), or matching Apple Command Line
Tools. The SDK must be macOS 26 or newer; the deployment target remains macOS 14.
GitHub Actions runs the same tests on every pull request; run them locally first. Homebrew
and other package managers are optional integrations, not build dependencies. You
do not need signing credentials to contribute.

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

To check UI changes without touching your real apps or settings, build a separate
preview copy with sample data:

```sh
swift build
open -n "$(bash script/package_ui_fixture.sh)" --args --ui-fixture --ui-fixture-dark
```

Add `--ui-fixture-route=Homebrew` to open a sidebar page, `--ui-fixture-settings=Sources`
to open a Settings section, `--ui-fixture-batch` for the batch review sheet, or
`--ui-fixture-light` for light appearance. Preview options only exist in debug builds.

## Where to work

- `Sources/Upkeep/Views`: SwiftUI windows, lists, settings, and inspectors.
- `Sources/Upkeep/Services`: discovery, publisher requests, package commands,
  installation, self-update, diagnostics, and backups.
- `Sources/Upkeep/Stores` and `UpkeepStore.swift`: state and operation coordination.
- `Sources/Upkeep/Models`: data types, settings, and update plans.
- `Sources/Upkeep/Support`: small shared helpers.
- `Sources/Upkeep/Resources/ThirdPartyLogos`: bundled logos. Add each new logo's
  owner, source, and terms to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- `Tests/UpkeepTests`: Swift Testing fixtures and regression tests.
- `script`: the run script and the UI preview build.
- `scripts`: packaging, release signing and validation, and performance measurements.

## Pull requests

1. Create a branch from current `main`; keep unrelated changes separate.
2. Explain the problem, resulting behaviour, and how you verified it.
3. Run the test command above. For update, install, or uninstall changes, add a
   regression test using temporary directories and injected dependencies, not real
   installed apps or packages.
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
