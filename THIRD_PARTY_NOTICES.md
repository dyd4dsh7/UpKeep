# Third-party notices

Upkeep's original code and artwork are covered by [LICENSE](LICENSE). Third-party
software, operating-system resources, and trademarks are not relicensed by that
file.

## Build and test tools

Tests use the Swift Testing framework, macro plugin and runtime supplied by the
selected Swift toolchain. Upkeep has no external Swift package dependencies and
no independently pinned Swift Testing or SwiftSyntax build. Swift Testing is
licensed under Apache 2.0 with Runtime Library Exception; see its
[distribution guidance](https://github.com/swiftlang/swift-testing/blob/swift-6.4.2-RELEASE/Documentation/Distributions.md).

The unmodified Swift Testing and SwiftSyntax licence texts in `Support/Licenses/`
are retained from earlier package-based test builds and included in app packages
for historical attribution. These testing libraries are not bundled in the app.

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
