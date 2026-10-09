import Foundation

public struct SearchLocation: Sendable, Hashable {
    public let url: URL
    public let category: LeftoverCategory
    /// Look one level into vendor folders, e.g. `Application Support/Google/Chrome`.
    public let descendIntoVendorFolders: Bool
    /// Files are named `Executable-date.ips`.
    public let isCrashReports: Bool

    public init(url: URL, category: LeftoverCategory, descendIntoVendorFolders: Bool = false, isCrashReports: Bool = false) {
        self.url = url
        self.category = category
        self.descendIntoVendorFolders = descendIntoVendorFolders
        self.isCrashReports = isCrashReports
    }
}

public enum SearchLocations {
    /// All places where apps typically leave files.
    /// - Parameters:
    ///   - home: user home (injectable for tests)
    ///   - systemRoot: `/` in production (injectable for tests)
    ///   - darwinCacheRoot: `$TMPDIR/../C` – per-user Darwin cache dir
    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemRoot: URL = URL(fileURLWithPath: "/"),
        darwinCacheRoot: URL? = defaultDarwinCacheRoot
    ) -> [SearchLocation] {
        let user = home.appendingPathComponent("Library")
        let system = systemRoot.appendingPathComponent("Library")

        func u(_ p: String, _ c: LeftoverCategory, vendor: Bool = false, crash: Bool = false) -> SearchLocation {
            SearchLocation(url: user.appendingPathComponent(p), category: c, descendIntoVendorFolders: vendor, isCrashReports: crash)
        }
        func s(_ p: String, _ c: LeftoverCategory, vendor: Bool = false, crash: Bool = false) -> SearchLocation {
            SearchLocation(url: system.appendingPathComponent(p), category: c, descendIntoVendorFolders: vendor, isCrashReports: crash)
        }

        var list: [SearchLocation] = [
            // ~/Library
            u("Application Support", .applicationSupport, vendor: true),
            u("Caches", .caches, vendor: true),
            u("Preferences", .preferences),
            u("Preferences/ByHost", .preferences),
            u("Containers", .containers),
            u("Group Containers", .containers),
            u("Application Scripts", .containers),
            u("Saved Application State", .savedState),
            u("HTTPStorages", .webData),
            u("WebKit", .webData),
            u("Cookies", .webData),
            u("Logs", .logs, vendor: true),
            u("Logs/DiagnosticReports", .logs, crash: true),
            u("LaunchAgents", .launchItems),
            u("Internet Plug-Ins", .extensions),
            u("PlugIns", .extensions),
            u("PreferencePanes", .extensions),
            u("QuickLook", .extensions),
            u("Services", .extensions),
            u("Screen Savers", .extensions),
            u("Spotlight", .extensions),
            u("Frameworks", .other),
            // /Library
            s("Application Support", .applicationSupport, vendor: true),
            s("Caches", .caches, vendor: true),
            s("Preferences", .preferences),
            s("Logs", .logs, vendor: true),
            s("Logs/DiagnosticReports", .logs, crash: true),
            s("LaunchAgents", .launchItems),
            s("LaunchDaemons", .launchItems),
            s("PrivilegedHelperTools", .launchItems),
            s("Internet Plug-Ins", .extensions),
            s("PreferencePanes", .extensions),
            s("QuickLook", .extensions),
            s("Screen Savers", .extensions),
            s("Spotlight", .extensions),
            s("Audio/Plug-Ins/HAL", .extensions),
            s("Audio/Plug-Ins/Components", .extensions),
            s("Frameworks", .other),
            SearchLocation(url: systemRoot.appendingPathComponent("private/var/db/receipts"), category: .receipts),
        ]
        if let darwinCacheRoot {
            list.append(SearchLocation(url: darwinCacheRoot, category: .caches))
        }
        return list
    }

    public static var defaultDarwinCacheRoot: URL? {
        // $TMPDIR = /var/folders/xx/yyyy/T/  →  /var/folders/xx/yyyy/C/
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let c = tmp.deletingLastPathComponent().appendingPathComponent("C")
        return FileManager.default.fileExists(atPath: c.path) ? c : nil
    }
}
