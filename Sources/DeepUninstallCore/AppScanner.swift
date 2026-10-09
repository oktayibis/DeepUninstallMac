import Foundation
import Security

public enum AppBundleReader {
    /// Reads metadata of a `.app` bundle. Reads Info.plist directly to avoid `Bundle` caching.
    public static func read(_ url: URL) -> AppInfo? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = (NSDictionary(contentsOf: infoURL) as? [String: Any]) ?? [:]

        func string(_ key: String) -> String? {
            guard let v = info[key] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return v
        }

        return AppInfo(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: string("CFBundleIdentifier"),
            bundleName: string("CFBundleName"),
            displayName: string("CFBundleDisplayName"),
            executableName: string("CFBundleExecutable"),
            version: string("CFBundleShortVersionString") ?? string("CFBundleVersion"),
            teamID: teamID(for: url)
        )
    }

    /// Team identifier from the code signature (no validation, fast).
    public static func teamID(for url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

public enum AppScanner {
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Finds all user-removable apps (searches up to 3 levels deep, e.g. `/Applications/Vendor/Tool.app`).
    public static func scanInstalledApps(roots: [URL] = defaultRoots) -> [AppInfo] {
        let fm = FileManager.default
        var urls: [URL] = []
        var seen = Set<String>()

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    let key = url.resolvingSymlinksInPath().path
                    if seen.insert(key).inserted, !isSystemApp(url) { urls.append(url) }
                } else if enumerator.level >= 3 {
                    enumerator.skipDescendants()
                }
            }
        }

        return Parallel.map(urls) { AppBundleReader.read($0) }
            .compactMap { $0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Apps on the sealed system volume (Safari, etc.) cannot be removed.
    static func isSystemApp(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        if resolved.hasPrefix("/System/") { return true }
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true
    }
}
