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

## Third-party product names

Names such as Homebrew, GitHub, Python, Node.js, npm, Ollama, and LM Studio
identify tools with which Upkeep interoperates. Upkeep is an independent project
and does not claim sponsorship or endorsement by those projects or their owners.
npm is a registered trademark of npm, Inc. Node.js is a registered trademark of
the OpenJS Foundation. "Python" is a registered trademark of the Python Software
Foundation.

## Third-party logos

The logos in `Sources/Upkeep/Resources/ThirdPartyLogos/` are bundled to identify
the tool that manages an item in Upkeep's lists. **They are trademarks of their
respective owners and are not covered by Upkeep's MIT licence.** Using them in
Upkeep does not grant you any right to use them elsewhere; check each owner's
terms below. Each logo was downloaded from its official source on 22 November
2026 and is unmodified unless a change is listed.

Logos are included only where the owner's policy or the file's licence permits
this use. These brands are shown with a generic system symbol instead because
their policy requires permission or no usable licence was found: npm, Node.js,
Visual Studio Code, Go, Ollama, Python, .NET, uv, Volta, MacPorts, asdf, and fnm.

| File | Owner | Source | Terms | Changes |
| --- | --- | --- | --- | --- |
| `bun.png` | Oven (Bun) | [bun.com/press-kit](https://bun.com/press-kit) (`logo@4x.png`) | Press-kit guidance: do not stretch, recolour, or alter | None |
| `cargo.png` | Rust Foundation | [rust-lang/cargo](https://github.com/rust-lang/cargo/blob/master/doc/book/src/images/Cargo-Logo-Small.png) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); [Rust trademark policy](https://rustfoundation.org/policy/rust-trademark-policy/) | None |
| `composer.png` | Composer (Jordi Boggiano, Nils Adermann); logo by Max Grigorian | [composer/getcomposer.org](https://github.com/composer/getcomposer.org/blob/main/web/img/logo-composer-transparent.png) | MIT (notice below) | None |
| `deno.svg` | Deno Land Inc. | [deno.com/brand](https://deno.com/brand) (dark filled mark) | Deno logo guidelines: black and white only, do not edit | None |
| `github.svg`, `github-dark.svg` | GitHub, Inc. | [primer/octicons](https://github.com/primer/octicons) `mark-github` | [GitHub logo guidelines](https://brand.github.com/foundations/logo); Octicons MIT (notice below) | `github-dark.svg` fills the mark white, matching GitHub's official white logo |
| `homebrew.svg` | Homebrew | [Homebrew/brew.sh](https://github.com/Homebrew/brew.sh/blob/main/assets/img/homebrew.svg) | BSD 2-Clause (notice below) | None |
| `lmstudio.svg` | LM Studio | [lmstudio.ai/brand](https://lmstudio.ai/brand) (`LM Studio Icon Color.svg`) | LM Studio brand terms: use when referring to LM Studio; non-exclusive, non-transferable, revocable | None |
| `mise.svg`, `mise-dark.svg` | Jeff Dickey (mise) | [jdx/mise](https://github.com/jdx/mise/tree/main/docs/public) (`logo-light.svg`, `logo-dark.svg`) | MIT (notice below) | None |
| `nix.png` | The NixOS Project and contributors; designed by Simon Frankau and Tim Cuthbertson | [NixOS/nixos-artwork](https://github.com/NixOS/nixos-artwork/blob/master/logo/nix-snowflake-colours.svg) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Rendered from SVG to a 512 px PNG; artwork unchanged |
| `pipx.svg` | pipx (Chad Smith and contributors); logo by @IrishMorales | [pypa/pipx](https://github.com/pypa/pipx/blob/main/logo.svg) | MIT (notice below) | None |
| `pnpm.svg` | pnpm (Zoltan Kochan and contributors) | [pnpm.io/logos](https://pnpm.io/logos) | MIT (notice below) | None |
| `rubygems.png` | Ruby Central (RubyGems) | [rubygems.org/logos.zip](https://rubygems.org/pages/about) (`rubygems_logo_red.png`) | Offered for download by RubyGems.org | None |
| `rustup.svg`, `rustup-dark.svg` | Rust Foundation | [rust-lang/rust-artwork](https://github.com/rust-lang/rust-artwork/blob/master/logo/rust-logo-single-path.svg) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); [Rust trademark policy](https://rustfoundation.org/policy/rust-trademark-policy/) | `rustup-dark.svg` fills the logo white for dark appearance |
| `yarn.svg` | Yarn | [yarnpkg/assets](https://github.com/yarnpkg/assets/blob/master/yarn-kitten-circle.svg) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | None |

Attribution for CC BY 4.0 works: "Nix snowflake" by Simon Frankau and Tim
Cuthbertson, the NixOS Project and contributors; "Rust logo" and "Cargo logo" by
the Rust Foundation; "Yarn logo" by the Yarn project. Each is licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), with changes as listed
above. CC BY 4.0 does not grant trademark rights.

### MIT notices for logo files

The following copyright notices apply to the logo files named above, each under
the MIT licence text that follows:

- Composer logo: Copyright (c) 2016 Jordi Boggiano, Nils Adermann
- Octicons (`mark-github`): Copyright (c) 2026 GitHub Inc.
- mise logos: Copyright (c) 2025 Jeff Dickey
- pipx logo: Copyright (c) 2018 Chad Smith and contributors
- pnpm logo: Copyright (c) 2016-2022 Zoltan Kochan and other contributors

> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in
> the Software without restriction, including without limitation the rights to
> use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
> the Software, and to permit persons to whom the Software is furnished to do so,
> subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
> FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
> COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
> AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
> WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### BSD 2-Clause notice for the Homebrew logo

> Copyright (c) 2009-present, Homebrew contributors. All rights reserved.
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this
>    list of conditions and the following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice,
>    this list of conditions and the following disclaimer in the documentation
>    and/or other materials provided with the distribution.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
> ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
> WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
> ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
> (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
> LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
> ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
> (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
> SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Historical artwork in older commits

Older commits contain an earlier set of logos whose sources were not recorded.
They are not part of current builds, and the MIT licence grants no rights in
them. Do not redistribute that historical artwork without checking its owner's
terms.
