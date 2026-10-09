import Foundation

/// An application bundle found on disk.
public struct AppInfo: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    /// File name without `.app` – what the user sees in Finder.
    public let name: String
    public let bundleID: String?
    public let bundleName: String?
    public let displayName: String?
    public let executableName: String?
    public let version: String?
    public let teamID: String?

    public init(
        url: URL,
        name: String,
        bundleID: String?,
        bundleName: String? = nil,
        displayName: String? = nil,
        executableName: String? = nil,
        version: String? = nil,
        teamID: String? = nil
    ) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.bundleName = bundleName
        self.displayName = displayName
        self.executableName = executableName
        self.version = version
        self.teamID = teamID
    }
}

/// Where a leftover lives. Order of cases = display order.
public enum LeftoverCategory: String, CaseIterable, Sendable, Comparable {
    case application
    case applicationSupport
    case caches
    case preferences
    case containers
    case savedState
    case webData
    case logs
    case launchItems
    case extensions
    case receipts
    case other

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum Confidence: Int, Comparable, Sendable {
    case low = 0, medium, high
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why a file was considered to belong to an app.
public enum MatchKind: String, Sendable {
    case appBundle        // the .app itself
    case bundleID         // exact bundle identifier
    case bundleIDPrefix   // com.foo.Bar.helper, ByHost plists …
    case teamGroup        // TEAMID.com.foo group container
    case name             // folder named exactly like the app
    case crashReport      // AppName-2026-…ips
    case partialName      // name contained in file name (weak)
    case orphan           // reverse-DNS file with no installed owner
}

/// A single file or folder proposed for removal.
public struct LeftoverItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let category: LeftoverCategory
    public let confidence: Confidence
    public let matchKind: MatchKind
    public var size: Int64
    public let requiresAdmin: Bool

    public init(url: URL, category: LeftoverCategory, confidence: Confidence, matchKind: MatchKind, size: Int64 = 0, requiresAdmin: Bool = false) {
        self.url = url
        self.category = category
        self.confidence = confidence
        self.matchKind = matchKind
        self.size = size
        self.requiresAdmin = requiresAdmin
    }

    /// Low-confidence matches are shown but not pre-selected.
    public var selectedByDefault: Bool { confidence >= .medium }
}

/// Leftovers of an app that is no longer installed, grouped by inferred bundle ID.
public struct OrphanGroup: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public var items: [LeftoverItem]
    /// Another installed app from the same vendor exists – these files may be shared.
    public let vendorHasInstalledApps: Bool
    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

public enum RemovalMode: Sendable {
    case trash, permanent
}

public struct RemovalFailure: Hashable, Sendable {
    public let url: URL
    public let message: String
}

public struct RemovalResult: Identifiable, Sendable {
    public let id = UUID()
    public var removed: [URL] = []
    public var failures: [RemovalFailure] = []
    public var skippedAdmin: Int = 0
    public var freedBytes: Int64 = 0
    public var mode: RemovalMode
    public init(mode: RemovalMode) { self.mode = mode }
}
