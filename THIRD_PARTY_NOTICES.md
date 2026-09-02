# Third-party notices

Upkeep's original code and artwork are covered by [LICENSE](LICENSE). Third-party
software, operating-system resources, and trademarks are not relicensed by that
file.

## Build and test dependencies

| Component | Pinned version | Licence | Source |
| --- | --- | --- | --- |
| Swift Testing | 6.1.3 | Apache 2.0 with Runtime Library Exception | https://github.com/swiftlang/swift-testing/tree/6.1.3 |
| SwiftSyntax | 601.0.1 | Apache 2.0 with Runtime Library Exception | https://github.com/swiftlang/swift-syntax/tree/601.0.1 |

Swift Testing is a test-target dependency; SwiftSyntax is its transitive build
dependency. Their unmodified licence texts are in `Support/Licenses/` and are
included in packaged apps. See `Package.resolved` for exact revisions.

## System images and installed application icons

Generic interface symbols are requested from macOS through SwiftUI/AppKit. Upkeep
does not bundle exported SF Symbols artwork. System resources remain subject to
Apple's terms. Icons read from locally installed apps belong to their respective
owners and are not included in this source distribution.

## Third-party product names and historical artwork

Names such as Homebrew, GitHub, Python, Ollama, and LM Studio identify tools with
which Upkeep interoperates. Upkeep is an independent project and does not claim
sponsorship or endorsement by those projects.

Bundled third-party package-manager and model-runtime logos were removed during
open-source preparation because their exact source and redistribution permissions
were not consistently recorded. The current source and new app packages use
native symbols. Older commits may still contain those images; the MIT licence
does not grant rights in them. See `docs/open-source-readiness.md` for the history
publication gate. Do not redistribute historical artwork without checking its
owner's terms.
