import Foundation
import Testing
@testable import Upkeep

@Test func appStoreLooksUpMacListingBeforeUniversalListing() {
    // macSoftware returned TestFlight's iPhone version (4.4.1) while the Mac
    // App Store offered 4.4.0; desktopSoftware matches the Mac App Store.
    #expect(AppStoreClient.lookupEntities == ["desktopSoftware", "macSoftware"])
}

@Test func nodeSkipsPrereleasesForStableInstalls() {
    let releases = ["27.0.0-alpha.0.1.1", "26.3.0", "26.2.0", "24.22.2", "24.22.1"]
    #expect(latestNodeRelease(in: releases, installed: "24.22.1", preferLatestMajor: true) == "26.3.0")
    #expect(latestNodeRelease(in: releases, installed: "24.22.1", preferLatestMajor: false) == "24.22.2")
    // An installed prerelease is already on that track.
    #expect(latestNodeRelease(in: releases, installed: "27.0.0-alpha.0.1.0", preferLatestMajor: false) == "27.0.0-alpha.0.1.1")
    #expect(latestNodeRelease(in: ["27.0.0-rc.1"], installed: "26.3.0", preferLatestMajor: true) == nil)
}

@Test func rubyGemsPrefersUserRubyOverSystemRuby() {
    let candidates = rubyGemExecutableCandidates(home: "/Users/test")
    #expect(candidates.first == "/Users/test/.rbenv/shims/gem")
    #expect(candidates.last == "/usr/bin/gem")
    #expect(candidates.firstIndex(of: "/opt/homebrew/opt/ruby/bin/gem")! < candidates.firstIndex(of: "/opt/homebrew/bin/gem")!)
}

@Test func rubyGemsUsesUserInstallOnlyForSystemRuby() {
    let system = DeveloperPackage(name: "bundler", currentVersion: "1.17.2", latestVersion: "2.7.0",
                                  manager: .rubyGems, executablePath: "/usr/bin/gem")
    let homebrew = DeveloperPackage(name: "bundler", currentVersion: "2.6.0", latestVersion: "2.7.0",
                                    manager: .rubyGems, executablePath: "/opt/homebrew/bin/gem")
    #expect(rubyGemInstallArguments(for: system, version: "2.7.0").last == "--user-install")
    #expect(rubyGemInstallArguments(for: homebrew, version: "2.7.0") == ["install", "bundler", "--version", "2.7.0"])
}
