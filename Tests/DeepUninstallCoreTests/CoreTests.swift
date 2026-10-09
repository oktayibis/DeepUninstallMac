import Foundation
import Testing
@testable import DeepUninstallCore

/// Builds a throw-away fake home + system root with a Library tree.
final class Sandbox {
    let root: URL
    let home: URL
    let system: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("du-tests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        system = root.appendingPathComponent("sys")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func make(_ relative: String, in base: URL? = nil, dir: Bool = false) throws -> URL {
        let url = (base ?? home).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dir ? url : url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !dir { try Data("x".utf8).write(to: url) }
        return url
    }

    var locations: [SearchLocation] { SearchLocations.standard(home: home, systemRoot: system, darwinCacheRoot: nil) }
}

let spotify = AppInfo(url: URL(fileURLWithPath: "/Applications/Spotify.app"), name: "Spotify",
                      bundleID: "com.spotify.client", bundleName: "Spotify", executableName: "Spotify", teamID: "2FNC3A47ZF")
let chrome = AppInfo(url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), name: "Google Chrome",
                     bundleID: "com.google.Chrome", bundleName: "Chrome", executableName: "Google Chrome", teamID: "EQHXZ8M8AV")
let drive = AppInfo(url: URL(fileURLWithPath: "/Applications/Google Drive.app"), name: "Google Drive",
                    bundleID: "com.google.drivefs", bundleName: "Google Drive", executableName: "Google Drive", teamID: "EQHXZ8M8AV")
let code = AppInfo(url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), name: "Visual Studio Code",
                   bundleID: "com.microsoft.VSCode", bundleName: "Code", executableName: "Electron")
let codeInsiders = AppInfo(url: URL(fileURLWithPath: "/Applications/Visual Studio Code - Insiders.app"), name: "Visual Studio Code - Insiders",
                           bundleID: "com.microsoft.VSCodeInsiders", bundleName: "Code - Insiders", executableName: "Electron")

@Suite struct MatcherTests {
    let id = AppIdentity(app: spotify)
    let others = OwnershipIndex(apps: [spotify, chrome], excluding: spotify)

    @Test func exactBundleID() {
        #expect(Matcher.match("com.spotify.client", identity: id, others: others)?.0 == .high)
        #expect(Matcher.match("com.spotify.client.plist", identity: id, others: others)?.0 == .high)
        #expect(Matcher.match("com.spotify.client.savedState", identity: id, others: others)?.0 == .high)
    }

    @Test func bundleIDPrefix() {
        #expect(Matcher.match("com.spotify.client.helper", identity: id, others: others)?.1 == .bundleIDPrefix)
        #expect(Matcher.match("com.spotify.client.8A1B-UUID.plist", identity: id, others: others) != nil)
    }

    @Test func doesNotMatchSiblingBundleIDs() {
        #expect(Matcher.match("com.spotify.clientpro", identity: id, others: others)?.1 != .bundleID)
        // Same vendor, different component: shown as uncertain, never preselected.
        #expect(Matcher.match("com.spotify.other", identity: id, others: others)?.0 == .low)
    }

    @Test func nameMatch() {
        #expect(Matcher.match("Spotify", identity: id, others: others)?.0 == .medium)
    }

    @Test func teamGroupContainer() {
        #expect(Matcher.match("2FNC3A47ZF.com.spotify.client", identity: id, others: others)?.0 == .high)
        #expect(Matcher.match("2FNC3A47ZF.shared", identity: id, others: others)?.0 == .medium)
    }

    @Test func sharedTeamIsWeak() {
        let o = OwnershipIndex(apps: [chrome, drive], excluding: chrome)
        #expect(Matcher.match("EQHXZ8M8AV.group.com.google", identity: AppIdentity(app: chrome), others: o)?.0 == .low)
    }

    @Test func neverMatchesApple() {
        #expect(Matcher.match("com.apple.Spotify", identity: id, others: others) == nil)
    }

    @Test func neverStealsOtherAppsFiles() {
        #expect(Matcher.match("com.google.Chrome", identity: id, others: others) == nil)
        #expect(Matcher.match("Google Chrome", identity: id, others: others) == nil)
    }

    @Test func moreSpecificInstalledAppWins() {
        let o = OwnershipIndex(apps: [code, codeInsiders], excluding: code)
        let i = AppIdentity(app: code)
        #expect(Matcher.match("Code", identity: i, others: o)?.0 == .medium)
        #expect(Matcher.match("Code - Insiders", identity: i, others: o) == nil)
        #expect(Matcher.match("com.microsoft.VSCodeInsiders", identity: i, others: o) == nil)
        #expect(Matcher.match("com.microsoft.VSCode.ShipIt", identity: i, others: o)?.0 == .high)
    }

    @Test func genericExecutableNameIgnored() {
        let o = OwnershipIndex(apps: [code], excluding: code)
        #expect(Matcher.match("Electron", identity: AppIdentity(app: code), others: o) == nil)
    }

    @Test func crashReports() {
        #expect(Matcher.match("Spotify-2026-10-08-101010.ips", identity: id, others: others, crashReports: true)?.1 == .crashReport)
    }
}

@Suite struct FinderTests {
    @Test func findsLeftoversAcrossLibrary() throws {
        let s = try Sandbox()
        try s.make("Library/Application Support/Spotify", dir: true)
        try s.make("Library/Caches/com.spotify.client/data.bin")
        try s.make("Library/Preferences/com.spotify.client.plist")
        try s.make("Library/Preferences/ByHost/com.spotify.client.ABC.plist")
        try s.make("Library/Saved Application State/com.spotify.client.savedState", dir: true)
        try s.make("Library/HTTPStorages/com.spotify.client", dir: true)
        try s.make("Library/LaunchAgents/com.spotify.webhelper.plist")    // other bundle ID → not matched
        try s.make("Library/Preferences/com.google.Chrome.plist")          // other app
        try s.make("Library/Preferences/com.apple.finder.plist")           // apple
        try s.make("Library/LaunchDaemons/com.spotify.client.helper.plist", in: s.system)

        let items = LeftoverFinder.find(for: spotify, installedApps: [spotify, chrome], locations: s.locations)
        let names = Set(items.map(\.url.lastPathComponent))

        #expect(names.contains("Spotify.app"))
        #expect(names.contains("Spotify"))
        #expect(names.contains("com.spotify.client"))
        #expect(names.contains("com.spotify.client.plist"))
        #expect(names.contains("com.spotify.client.ABC.plist"))
        #expect(names.contains("com.spotify.client.savedState"))
        #expect(names.contains("com.spotify.client.helper.plist"))
        #expect(!names.contains("com.google.Chrome.plist"))
        #expect(!names.contains("com.apple.finder.plist"))
        #expect(items.first { $0.url.lastPathComponent == "com.spotify.webhelper.plist" }?.selectedByDefault == false)
        #expect(items.first { $0.url.lastPathComponent == "com.spotify.client" && $0.category == .caches }!.size > 0)
    }

    @Test func descendsIntoVendorFolder() throws {
        let s = try Sandbox()
        try s.make("Library/Application Support/Google/Chrome", dir: true)
        try s.make("Library/Application Support/Google/DriveFS", dir: true)

        let items = LeftoverFinder.find(for: chrome, installedApps: [chrome, drive], locations: s.locations, computeSizes: false)
        let paths = items.map(\.url.path)
        #expect(paths.contains { $0.hasSuffix("Google/Chrome") })
        #expect(!paths.contains { $0.hasSuffix("Google/DriveFS") })
        #expect(!paths.contains { $0.hasSuffix("Application Support/Google") })
    }
}

@Suite struct OrphanTests {
    @Test func findsOrphans() throws {
        let s = try Sandbox()
        try s.make("Library/Preferences/com.oldvendor.OldApp.plist")
        try s.make("Library/Caches/com.oldvendor.OldApp", dir: true)
        try s.make("Library/Preferences/com.spotify.client.plist")        // installed
        try s.make("Library/Preferences/com.apple.dock.plist")            // apple
        try s.make("Library/Preferences/com.google.Keystone.plist")       // vendor has installed app
        try s.make("Library/Preferences/loginwindow.plist")               // not reverse-DNS

        let groups = OrphanFinder.find(installedApps: [spotify, chrome], locations: s.locations)
        let keys = Set(groups.map(\.key))
        #expect(keys == ["com.oldvendor.oldapp", "com.google.keystone"])
        #expect(groups.first { $0.key == "com.oldvendor.oldapp" }!.items.count == 2)
        #expect(groups.first { $0.key == "com.google.keystone" }!.vendorHasInstalledApps)
    }

    @Test func respectsLaunchServices() throws {
        let s = try Sandbox()
        try s.make("Library/Preferences/com.elsewhere.Tool.plist")
        let groups = OrphanFinder.find(installedApps: [], locations: s.locations, isRegisteredBundleID: { $0 == "com.elsewhere.Tool" })
        #expect(groups.isEmpty)
    }
}

@Suite struct RemoverTests {
    @Test func protectedPaths() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(Remover.isProtected(URL(fileURLWithPath: "/"), home: home))
        #expect(Remover.isProtected(URL(fileURLWithPath: "/Applications"), home: home))
        #expect(Remover.isProtected(URL(fileURLWithPath: "/Users/test/Library"), home: home))
        #expect(Remover.isProtected(URL(fileURLWithPath: "/Users/test/Library/Caches"), home: home))
        #expect(Remover.isProtected(URL(fileURLWithPath: "/System/Library/Foo"), home: home))
        #expect(!Remover.isProtected(URL(fileURLWithPath: "/Users/test/Library/Caches/com.foo"), home: home))
        #expect(!Remover.isProtected(URL(fileURLWithPath: "/Applications/Foo.app"), home: home))
    }

    @Test func permanentRemoval() async throws {
        let s = try Sandbox()
        let a = try s.make("Library/Caches/com.foo.bar/file")
        let dir = a.deletingLastPathComponent()
        let item = LeftoverItem(url: dir, category: .caches, confidence: .high, matchKind: .bundleID, size: 1)
        let result = await Remover.remove([item], mode: .permanent, allowAdmin: false)
        #expect(result.removed.count == 1)
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func adminItemsSkippedWhenNotAllowed() async throws {
        let s = try Sandbox()
        let f = try s.make("x/file")
        let item = LeftoverItem(url: f, category: .other, confidence: .high, matchKind: .bundleID, requiresAdmin: true)
        let result = await Remover.remove([item], mode: .permanent, allowAdmin: false)
        #expect(result.skippedAdmin == 1)
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func shellQuoting() {
        #expect(Remover.shellQuote("/a b/it's") == "'/a b/it'\\''s'")
    }
}
