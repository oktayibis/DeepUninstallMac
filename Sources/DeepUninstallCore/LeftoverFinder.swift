import Foundation

public enum LeftoverFinder {
    /// Finds the app bundle plus all leftovers belonging to `app`.
    public static func find(
        for app: AppInfo,
        installedApps: [AppInfo],
        locations: [SearchLocation] = SearchLocations.standard(),
        computeSizes: Bool = true
    ) -> [LeftoverItem] {
        let identity = AppIdentity(app: app)
        let others = OwnershipIndex(apps: installedApps, excluding: app)
        let appPath = app.url.standardizedFileURL.path
        let fm = FileManager.default

        var found: [String: LeftoverItem] = [:]
        found[appPath] = LeftoverItem(
            url: app.url, category: .application, confidence: .high, matchKind: .appBundle,
            requiresAdmin: Remover.requiresAdmin(app.url)
        )

        func add(_ url: URL, _ location: SearchLocation, _ match: (Confidence, MatchKind)) {
            let path = url.standardizedFileURL.path
            guard path != appPath, !path.hasPrefix(appPath + "/") else { return }
            if let existing = found[path], existing.confidence >= match.0 { return }
            found[path] = LeftoverItem(
                url: url, category: location.category, confidence: match.0, matchKind: match.1,
                requiresAdmin: Remover.requiresAdmin(url)
            )
        }

        for location in locations {
            guard let entries = try? fm.contentsOfDirectory(at: location.url, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent
                if name.hasPrefix(".") { continue }
                if let match = Matcher.match(name, identity: identity, others: others, crashReports: location.isCrashReports) {
                    add(entry, location, match)
                } else if location.descendIntoVendorFolders,
                          let vendor = identity.vendor,
                          Matcher.normalize(name) == vendor,
                          entry.isDirectoryURL,
                          let children = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) {
                    // Application Support/Google/Chrome
                    for child in children where !child.lastPathComponent.hasPrefix(".") {
                        if let match = Matcher.match(child.lastPathComponent, identity: identity, others: others) {
                            add(child, location, match)
                        }
                    }
                }
            }
        }

        var items = removeNested(Array(found.values))
        if computeSizes {
            items = Parallel.map(items) { item in
                var copy = item
                copy.size = FileSize.of(item.url)
                return copy
            }
        }
        return items.sorted {
            $0.category != $1.category ? $0.category < $1.category : $0.url.path < $1.url.path
        }
    }

    /// Drops items that live inside another selected item.
    static func removeNested(_ items: [LeftoverItem]) -> [LeftoverItem] {
        var kept: [LeftoverItem] = []
        for item in items.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let path = item.url.standardizedFileURL.path
            if !kept.contains(where: { path.hasPrefix($0.url.standardizedFileURL.path + "/") }) {
                kept.append(item)
            }
        }
        return kept
    }
}

public enum OrphanFinder {
    /// Finds reverse-DNS leftovers (`com.vendor.app…`) whose app is no longer installed.
    /// - Parameter isRegisteredBundleID: Launch Services lookup, injectable for tests.
    public static func find(
        installedApps: [AppInfo],
        locations: [SearchLocation] = SearchLocations.standard(),
        isRegisteredBundleID: @Sendable (String) -> Bool = { _ in false },
        computeSizes: Bool = true
    ) -> [OrphanGroup] {
        let installed = installedApps.compactMap { $0.bundleID?.lowercased() }
        let vendors = Set(installed.compactMap(vendorPrefix))
        let fm = FileManager.default
        var groups: [String: [LeftoverItem]] = [:]
        var registeredCache: [String: Bool] = [:]

        for location in locations where location.category != .receipts {
            guard let entries = try? fm.contentsOfDirectory(at: location.url, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                guard let (key, originalKey) = orphanKey(for: entry.lastPathComponent) else { continue }
                let stem = Matcher.stem(entry.lastPathComponent.lowercased())

                let owned = installed.contains { bid in
                    bid == key || bid.hasPrefix(key + ".") || key.hasPrefix(bid + ".") || stem == bid || stem.hasPrefix(bid + ".")
                }
                if owned { continue }

                let registered = registeredCache[key] ?? isRegisteredBundleID(originalKey)
                registeredCache[key] = registered
                if registered { continue }

                let vendorShared = vendorPrefix(key).map(vendors.contains) ?? false
                groups[key, default: []].append(LeftoverItem(
                    url: entry, category: location.category,
                    confidence: vendorShared ? .low : .medium, matchKind: .orphan,
                    requiresAdmin: Remover.requiresAdmin(entry)
                ))
            }
        }

        var result = groups.map { key, items in
            OrphanGroup(
                key: key,
                items: LeftoverFinder.removeNested(items),
                vendorHasInstalledApps: vendorPrefix(key).map(vendors.contains) ?? false
            )
        }
        if computeSizes {
            result = Parallel.map(result) { group in
                var g = group
                g.items = g.items.map { var i = $0; i.size = FileSize.of(i.url); return i }
                return g
            }
        }
        return result.sorted { $0.totalSize > $1.totalSize }
    }

    static let tlds: Set<String> = [
        "com", "org", "net", "io", "app", "co", "me", "de", "dev", "info", "biz", "us", "uk", "fr", "nl",
        "ch", "se", "jp", "cn", "ru", "tr", "it", "es", "ca", "au", "at", "be", "pl", "cz", "eu", "tv", "ai",
    ]

    /// `com.Foo.Bar.helper.plist` → (`com.foo.bar`, `com.Foo.Bar`)
    static func orphanKey(for filename: String) -> (String, String)? {
        var s = Matcher.stem(filename)
        if s.lowercased().hasPrefix("group.") { s.removeFirst("group.".count) }
        let comps = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard comps.count >= 3, comps.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard tlds.contains(comps[0].lowercased()) else { return nil }   // skips TEAMID.xxx and random files
        let original = comps.prefix(3).joined(separator: ".")
        let key = original.lowercased()
        if key.hasPrefix("com.apple.") { return nil }
        return (key, original)
    }

    static func vendorPrefix(_ bundleID: String) -> String? {
        let comps = bundleID.split(separator: ".")
        guard comps.count >= 2 else { return nil }
        return comps.prefix(2).joined(separator: ".")
    }
}
