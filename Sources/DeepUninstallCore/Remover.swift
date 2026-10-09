import Foundation

public enum Remover {
    // MARK: - Safety

    /// True if removing `url` needs root (parent not writable, or root-owned folder).
    public static func requiresAdmin(_ url: URL) -> Bool {
        let fm = FileManager.default
        if !fm.isWritableFile(atPath: url.deletingLastPathComponent().path) { return true }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, !fm.isWritableFile(atPath: url.path) {
            return true
        }
        return false
    }

    /// Paths that must never be removed, no matter what the matcher says.
    public static func isProtected(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        let comps = url.standardizedFileURL.pathComponents
        if comps.count < 3 { return true }  // "/", "/Users", "/Library", …

        let homePath = home.standardizedFileURL.path
        var exact: Set<String> = [
            "/Applications", "/Library", "/System", "/Users", "/private", "/var", "/usr",
            homePath, homePath + "/Library", homePath + "/Applications", homePath + "/Documents",
            homePath + "/Desktop", homePath + "/Downloads",
        ]
        exact.formUnion(SearchLocations.standard(home: home).map { $0.url.standardizedFileURL.path })
        if exact.contains(path) { return true }

        let forbiddenPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/private/etc/", "/Library/Apple/"]
        return forbiddenPrefixes.contains { path.hasPrefix($0) }
    }

    // MARK: - Removal

    /// Removes items. Items needing root are batched into a single password prompt if `allowAdmin`.
    public static func remove(_ items: [LeftoverItem], mode: RemovalMode, allowAdmin: Bool) async -> RemovalResult {
        await Task.detached(priority: .userInitiated) {
            performRemoval(items, mode: mode, allowAdmin: allowAdmin)
        }.value
    }

    static func performRemoval(_ items: [LeftoverItem], mode: RemovalMode, allowAdmin: Bool) -> RemovalResult {
        let fm = FileManager.default
        var result = RemovalResult(mode: mode)
        var adminQueue: [LeftoverItem] = []
        let userAgents = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path + "/"

        for item in items {
            if isProtected(item.url) {
                result.failures.append(.init(url: item.url, message: "Protected location"))
                continue
            }
            guard (try? fm.attributesOfItem(atPath: item.url.path)) != nil else {
                result.removed.append(item.url)  // already gone
                continue
            }
            if item.requiresAdmin {
                if allowAdmin { adminQueue.append(item) } else { result.skippedAdmin += 1 }
                continue
            }
            if item.url.path.hasPrefix(userAgents), item.url.pathExtension == "plist" {
                run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path])
            }
            do {
                switch mode {
                case .trash: try fm.trashItem(at: item.url, resultingItemURL: nil)
                case .permanent: try fm.removeItem(at: item.url)
                }
                result.removed.append(item.url)
                result.freedBytes += item.size
            } catch {
                if allowAdmin, isPermissionError(error) {
                    adminQueue.append(item)
                } else {
                    result.failures.append(.init(url: item.url, message: error.localizedDescription))
                }
            }
        }

        if !adminQueue.isEmpty {
            let failedIndices = runPrivileged(adminQueue, mode: mode)
            for (i, item) in adminQueue.enumerated() {
                if let message = failedIndices[i] {
                    result.failures.append(.init(url: item.url, message: message))
                } else {
                    result.removed.append(item.url)
                    result.freedBytes += item.size
                }
            }
        }
        return result
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EACCES) || underlying.code == Int(EPERM)
        }
        return ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM))
    }

    // MARK: - Privileged batch

    /// Runs one shell script as root via the standard macOS password dialog.
    /// Returns failure messages keyed by item index.
    static func runPrivileged(_ items: [LeftoverItem], mode: RemovalMode) -> [Int: String] {
        let fm = FileManager.default
        let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        var usedNames = Set<String>()
        var lines: [String] = []

        for (i, item) in items.enumerated() {
            let src = shellQuote(item.url.path)
            var cmd = ""
            if item.url.path.hasPrefix("/Library/LaunchDaemons/") {
                lines.append("/bin/launchctl bootout system \(src) >/dev/null 2>&1")
            }
            switch mode {
            case .permanent:
                cmd = "/bin/rm -rf \(src)"
            case .trash:
                let dest = shellQuote(uniqueTrashURL(for: item.url, in: trash, used: &usedNames).path)
                cmd = "/bin/mv \(src) \(dest) && /usr/sbin/chown -R \(getuid()) \(dest)"
            }
            lines.append("if ! { \(cmd); }; then echo FAIL:\(i); fi")
        }

        let script = lines.joined(separator: "\n")
        let appleScript = "do shell script \"\(appleScriptEscape(script))\" with administrator privileges"
        let (status, out, err) = run("/usr/bin/osascript", ["-e", appleScript])

        if status != 0 {
            let message = err.contains("-128") ? "Administrator authentication was cancelled" : err.trimmingCharacters(in: .whitespacesAndNewlines)
            return Dictionary(uniqueKeysWithValues: items.indices.map { ($0, message.isEmpty ? "Failed" : message) })
        }
        var failures: [Int: String] = [:]
        for line in out.split(separator: "\n") where line.hasPrefix("FAIL:") {
            if let i = Int(line.dropFirst(5)) { failures[i] = "Could not remove (permission denied)" }
        }
        return failures
    }

    static func uniqueTrashURL(for url: URL, in trash: URL, used: inout Set<String>) -> URL {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var name = url.lastPathComponent
        var n = 1
        while used.contains(name) || fm.fileExists(atPath: trash.appendingPathComponent(name).path) {
            n += 1
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        }
        used.insert(name)
        return trash.appendingPathComponent(name)
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

public enum PermissionChecker {
    /// The TCC database is only readable with Full Disk Access.
    public static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
        for url in probes {
            if let handle = try? FileHandle(forReadingFrom: url) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
