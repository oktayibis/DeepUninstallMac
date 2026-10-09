import Foundation

/// Normalized identifiers of the app being uninstalled.
public struct AppIdentity: Sendable {
    public let bundleID: String?        // lowercased
    public let names: Set<String>       // normalized (letters+digits), length >= 3
    public let rawNames: [String]       // lowercased, for crash report prefixes
    public let teamID: String?          // lowercased
    public let vendor: String?          // normalized 2nd bundle-ID component

    /// Names too generic to identify an app on their own.
    static let genericNames: Set<String> = [
        "app", "apps", "helper", "client", "launcher", "update", "updater", "agent", "service",
        "desktop", "mac", "macos", "osx", "pro", "electron", "main", "application", "run", "start",
        "default", "data", "cache", "caches", "logs", "plugins", "support", "preferences", "tools",
    ]

    public init(app: AppInfo) {
        bundleID = app.bundleID?.lowercased()
        teamID = app.teamID?.lowercased()

        let raw = [app.name, app.bundleName, app.displayName, app.executableName]
            .compactMap { $0?.lowercased() }
        rawNames = Array(Set(raw)).filter { $0.count >= 3 && !Self.genericNames.contains(Matcher.normalize($0)) }
        names = Set(raw.map(Matcher.normalize).filter { $0.count >= 3 && !Self.genericNames.contains($0) })

        if let comps = bundleID?.split(separator: "."), comps.count >= 3 {
            let v = Matcher.normalize(String(comps[1]))
            vendor = (v.count >= 3 && v != "apple") ? v : nil
        } else {
            vendor = nil
        }
    }
}

/// Identifiers of every *other* installed app – used to avoid stealing their files.
public struct OwnershipIndex: Sendable {
    public let bundleIDs: [String]
    public let names: Set<String>
    public let teamIDCounts: [String: Int]

    public init(apps: [AppInfo], excluding target: AppInfo) {
        let identity = AppIdentity(app: target)
        let others = apps.filter { $0.url.standardizedFileURL != target.url.standardizedFileURL }
        bundleIDs = Array(Set(others.compactMap { $0.bundleID?.lowercased() }).subtracting([identity.bundleID ?? ""]))
        var n = Set<String>()
        var t: [String: Int] = [:]
        for app in others {
            n.formUnion(AppIdentity(app: app).names)
            if let team = app.teamID?.lowercased(), app.bundleID?.lowercased() != identity.bundleID { t[team, default: 0] += 1 }
        }
        names = n.subtracting(identity.names)
        teamIDCounts = t
    }
}

public enum Matcher {
    static let strippableExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "log", "ips", "crash", "diag", "bom", "spin", "hang", "lockfile",
    ]

    /// Lowercase, letters & digits only. "Visual Studio Code" → "visualstudiocode"
    public static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Strips well-known leftover file extensions (max. 2), e.g. `com.foo.plist.lockfile` → `com.foo`.
    static func stem(_ filename: String) -> String {
        var s = filename
        for _ in 0..<2 {
            let ext = (s as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, strippableExtensions.contains(ext) else { break }
            s = (s as NSString).deletingPathExtension
        }
        return s
    }

    /// Decides whether a directory entry belongs to the app.
    public static func match(
        _ filename: String,
        identity: AppIdentity,
        others: OwnershipIndex,
        crashReports: Bool = false
    ) -> (Confidence, MatchKind)? {
        let lower = filename.lowercased()
        var s = stem(lower)
        if s.hasPrefix("group.") { s.removeFirst("group.".count) }

        func ownedByOther(_ candidate: String, longerThan minLength: Int = 0) -> Bool {
            others.bundleIDs.contains { $0.count > minLength && (candidate == $0 || candidate.hasPrefix($0 + ".")) }
        }

        // 1. Bundle identifier
        if let bid = identity.bundleID {
            if s == bid { return (.high, .bundleID) }
            if s.hasPrefix(bid + ".") {
                // e.g. uninstalling com.foo.app must not take com.foo.app.pro (another installed app)
                if ownedByOther(s, longerThan: bid.count) { return nil }
                return (.high, .bundleIDPrefix)
            }
        }

        // 2. Team-ID group containers: ABCDE12345.com.foo.shared
        if let team = identity.teamID, s.hasPrefix(team + ".") {
            let rest = String(s.dropFirst(team.count + 1))
            if let bid = identity.bundleID, rest == bid || rest.hasPrefix(bid + ".") { return (.high, .teamGroup) }
            if ownedByOther(rest) { return nil }
            // Shared with other installed apps of the same developer → weak.
            return others.teamIDCounts[team, default: 0] > 0 ? (.low, .teamGroup) : (.medium, .teamGroup)
        }

        // Never touch Apple's files or files of other installed apps.
        if s.hasPrefix("com.apple.") || lower.hasPrefix("com.apple.") { return nil }
        if ownedByOther(s) { return nil }

        let ns = normalize(s)
        guard ns.count >= 3 else { return nil }
        if others.names.contains(ns) { return nil }

        // 3. Exact name: "Application Support/Spotify"
        if identity.names.contains(ns) { return (.medium, .name) }

        // 4. Crash reports: "Spotify-2026-10-08-101010.ips"
        if crashReports {
            for raw in identity.rawNames where lower.hasPrefix(raw + "-") || lower.hasPrefix(raw + "_") || lower.hasPrefix(raw + ".") {
                return (.medium, .crashReport)
            }
        }

        // 5. Reverse-DNS whose last component is the app name (e.g. old bundle ID): weak.
        let comps = s.split(separator: ".")
        if comps.count >= 3, let last = comps.last, identity.names.contains(normalize(String(last))) {
            return (.low, .partialName)
        }

        // 6. Name contained in file name: weak, not preselected.
        for n in identity.names where n.count >= 5 && ns.contains(n) {
            // "Code" vs "Code Insiders": a longer, more specific installed name wins.
            if others.names.contains(where: { $0.count > n.count && ns.contains($0) }) { return nil }
            return (.low, .partialName)
        }
        return nil
    }
}
