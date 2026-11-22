# Open-source readiness review

Review started 3 September 2026 against `250b38c` (private `dyd4dsh7/UpKeep`).
This is a dated audit record, not an evergreen guarantee of security or legal clearance.

## Secret and privacy review

- Gitleaks 8.30.1, verified against upstream checksums, scanned all locally
  available refs with `git --log-opts="--all"`: 39 non-merge commits scanned,
  no findings. The repository contained 41 reachable commits including merges.
- Downloaded and scanned all 15 existing GitHub Actions logs (approximately
  2.89 MB): no findings. There were no retained Actions artifacts or releases.
- A separate pattern/filename pass found no tracked private keys, certificate
  exports, environment files, or hard-coded developer home paths. Synthetic
  token fixtures exist in the diagnostic-redaction tests.
- Reviewed tracked documentation and the Codex run configuration. The run
  configuration contains only a local script action. Performance reports use
  synthetic fixtures. The historical log-review document includes real app names,
  timings and operating-system observations; it is not a raw diagnostic export.
- Commit authorship/metadata and historical reports become visible with history.
  Local outputs, work files, builds and distribution archives remain ignored.
- No real credentials were printed or copied into a repository file. Audit logs,
  scanner reports, and removed-asset backups are under ignored
  `outputs/open-source-audit/`.

These are automated and targeted manual checks, not a comprehensive security
assessment. Newly added refs, logs, artifacts and screenshots need their own review.

## Licensing and assets

MIT is prepared for original Upkeep code and artwork. The repository's observed
commit author is Hayden Thorn. The owner must have the rights to grant this
licence; neither commit attribution nor this audit establishes ownership.

Swift Testing 6.1.3 and SwiftSyntax 601.0.1 licence texts were read from the resolved
upstream checkouts and copied unchanged into `Support/Licenses/`. Both use
Apache 2.0 with the Runtime Library Exception. Notices are included in packaged apps.

The 26 third-party logos below were removed from current source and replaced by
macOS system symbols because exact asset provenance and transferable redistribution
rights were not recorded. A public brand download is not necessarily an open-source
asset licence. For example, [LM Studio's brand terms](https://lmstudio.ai/brand)
grant non-transferable, revocable use, and [Simple Icons' disclaimer](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md)
warns that its package licence does not establish every brand icon's licence.

| Removed asset | SHA-256 of the audited file |
| --- | --- |
| `Sources/Upkeep/Resources/PackageManagers/asdf.svg` | `f42fa209c0c3baea0485d2a3f98b8e51e9b8283bdd2683c9095b722a7806f1d0` |
| `Sources/Upkeep/Resources/PackageManagers/bun.png` | `8742a3f70a496409a7a9b043e5001bfa3494cbf9395ee694813b72690dc83f3f` |
| `Sources/Upkeep/Resources/PackageManagers/cargo.png` | `afc96eaf2a1702ecb17431a0c8cca5dbb629d9357ff52c30c7d210631014ee1e` |
| `Sources/Upkeep/Resources/PackageManagers/composer.svg` | `809bdad1d19d778dd3d95f8c160aa7ae58faff5870c87db1f0348e02178313f5` |
| `Sources/Upkeep/Resources/PackageManagers/deno.png` | `d68c8feae715c2ebf6b1dcbe42e085bb88ef2968970171f1f4c9c38ac044c2e1` |
| `Sources/Upkeep/Resources/PackageManagers/dotnet.svg` | `90873de3224ce974fd8a4300816d5bc1db44272f1f21e25f23b2341b0d29b9cf` |
| `Sources/Upkeep/Resources/PackageManagers/fnm.svg` | `3d018a28e0558132eb3202eb4833e50cf508480c4e14091f8257c114beba92aa` |
| `Sources/Upkeep/Resources/PackageManagers/github.svg` | `abdb620acbc29daf281e1f616fe41f1a9376bcb76e5ccc5fcca0fe09224b38b1` |
| `Sources/Upkeep/Resources/PackageManagers/go.svg` | `c0c397d3062a3be651e8e7024e64c604559361b016ad76df12447bf172760d99` |
| `Sources/Upkeep/Resources/PackageManagers/homebrew.png` | `52430ed9173af99d6c83dc603cce525287677829f5ca0a7856817d0288ed6318` |
| `Sources/Upkeep/Resources/PackageManagers/macports.svg` | `f8b272e2bb9942ef9fb7f89e15153c3a3e24e0f207174c67d34bc05c004cb877` |
| `Sources/Upkeep/Resources/PackageManagers/mise.svg` | `5840deb18468062ffbd8159c813607468cbbc36512bbb85a4aba6f75f30e5815` |
| `Sources/Upkeep/Resources/PackageManagers/nix.svg` | `cbddb07e94ee9f72033ae6e470bc7c60716a4fc3c848d0b00a269cc77b2bcf6e` |
| `Sources/Upkeep/Resources/PackageManagers/node.png` | `bb8276d2678dc3c939f3aed80d297c6eef5e444cce65f3f361a0be360956deab` |
| `Sources/Upkeep/Resources/PackageManagers/npm.png` | `10fa8041e6aa6048f0411da1e17b259b7d5466d2eeedd7574208cf1113a63b28` |
| `Sources/Upkeep/Resources/PackageManagers/pipx.svg` | `35dc9242317ea1a5442b77aebf86fac547b0cbb6a490ac9a5fcc3b6ccfbb7a49` |
| `Sources/Upkeep/Resources/PackageManagers/pnpm.png` | `a9a6ffbae831f99bd8ae3f2c15a99f704b3bcf3e25fea6f91fec4dc8391c339b` |
| `Sources/Upkeep/Resources/PackageManagers/python.png` | `8a5117d4036e688d97b1aaae730dffae295a2151ebdb5a2d8f9184d43c199f05` |
| `Sources/Upkeep/Resources/PackageManagers/rubygems.png` | `66022210c416663a43ef106c3ff4126f42f49a8cc8b439a17b6b76bd17c43202` |
| `Sources/Upkeep/Resources/PackageManagers/rustup.svg` | `562096eed34c4475dfd6af6ba7252feae8e5159afef647b17e203ebedb332e56` |
| `Sources/Upkeep/Resources/PackageManagers/uv.svg` | `3539005448ed2a0620a25d994f1c34ffd5a9c91939986b234e7d3087e97f68b9` |
| `Sources/Upkeep/Resources/PackageManagers/volta.svg` | `96ba8fd25151d465d9d0319add3deb9230fdf5577c8585555349e4098c4e816a` |
| `Sources/Upkeep/Resources/PackageManagers/vscode.svg` | `9a5ad8fe6fb23c9e966b589ba94a90c233561dd33a30959c7af04523fbc04b59` |
| `Sources/Upkeep/Resources/PackageManagers/yarn.png` | `34e918a4c6e315341a20f48589b964dddcc9412c32c237e852c46945c55d0887` |
| `Sources/Upkeep/Resources/LLMRuntimes/lmstudio.png` | `e79ff2ac0fece5c0a76fcb8b20a29226794d11824ee7c7a2f521dcde0f88e12b` |
| `Sources/Upkeep/Resources/LLMRuntimes/ollama.png` | `8a5d4f0444d756d1d64c6615eb163ecd71fba180bd07c4199e88461c921778d1` |

### History publication gate

Removing an image from the latest tree does not remove it from previous commits.
Before making this existing repository public, either establish redistribution
rights for its historical assets, or publish the cleaned tree with new history
while keeping this original history privately archived. No history rewrite,
repository rename, deletion, or visibility change is performed by this audit.

**Decision, 22 November 2026:** the owner chose to publish this repository with
its existing history. The historical logos remain in older commits and are
documented as not covered by the MIT licence. Separately, logos for brands whose
policies or file licences permit identification use were restored from official
sources into `Sources/Upkeep/Resources/ThirdPartyLogos/`, with per-file sources,
terms, and notices in `THIRD_PARTY_NOTICES.md`. Brands requiring permission keep
system symbols.

## Build and release gates

CI now selects Xcode 26.3 on `macos-26`, tests with compiler warnings as errors,
packages and launches a debug app, checks included notices, verifies signing, and
ensures debug artifacts cannot pass release validation. A separate required job
scans Git history. Actions and the downloaded secret scanner are pinned.

The local macOS 27 beta Command Line Tools lacks its SwiftUI macro plugin. Use the
installed stable macOS 26.5 SDK for local verification, and the pinned Xcode CI
job for the supported contributor toolchain.

There are currently no GitHub signing secrets and no valid local code-signing
identities. A signed/notarized release cannot be produced until the maintainer
supplies credentials through the protected `release` environment. The release
workflow refuses to substitute debug artifacts and creates drafts only after
signing, notarization and validation succeed. See [releasing.md](releasing.md).

## Verification results

- All 214 local tests passed with compiler warnings treated as errors using the
  installed stable macOS 26.5 SDK.
- Debug packaging and process launch passed. The bundle includes MIT and dependency
  notices, contains no removed logos, and passes strict code-signature validation.
  Release validation correctly rejects its ad-hoc signature.
- The Xcode 26.3 CI jobs passed on `3884b59`, including startup after temporary build
  directory cleanup. Subsequent commits remain subject to the PR's required checks:
  https://github.com/dyd4dsh7/UpKeep/pull/2
- Reproduced and fixed a local SwiftUI navigation crash by removing animation around
  outgoing destination hierarchies. Verified navigation between Updates, Developer,
  and AI Models. No package installation, cleanup, restore, or application update
  was performed during these UI checks.
- Checked the Developer list and inspector at approximately 1,492 and 760 points
  wide. Added a stacked row layout where version controls previously hid names.
  Private screenshots remain in the ignored audit directory. The README screenshot
  contains only the Settings interface, without app inventories or personal paths.
- Actionlint 1.7.12 passed (ShellCheck not installed); YAML parsing, shell syntax,
  diff whitespace, and valid/missing/invalid release-note checks passed.

## Repository safeguards applied

- `main` requires a pull request and current passing `test-and-package` and
  `secret-scan` checks from GitHub Actions. Admins are included. Force pushes and
  branch deletion are prohibited; conversations must be resolved. A separate
  approval is not required for this sole-maintainer project.
- Active `v*` tag rules restrict creation, updates, and deletion to repository
  admins through an explicit bypass role.
- The `release` environment permits only `main` and `v*` tags. There are no signing
  secrets in it yet. Add its maintainer approval gate when publishing publicly.
- Dependency vulnerability alerts are enabled. Default Actions token permissions
  are read-only and Actions cannot approve pull requests.
- Private vulnerability reporting and external-fork approval settings are not
  available on this private repository through the checked API. Enable those,
  secret scanning and push protection after public creation; do not claim them
  enabled until their state is read back.
- Repository visibility is still private. Source publication/history handling and
  signed binary publication remain distinct final steps requiring the outstanding
  history decision and Apple signing credentials respectively.
