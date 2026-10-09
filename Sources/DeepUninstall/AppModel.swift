import AppKit
import DeepUninstallCore
import SwiftUI

enum SidebarItem: Hashable {
    case app(String)
    case orphans
}

enum AppSortOrder: String, CaseIterable, Identifiable {
    case name, size
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .size: String(localized: "Size")
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var apps: [AppInfo] = []
    var appSizes: [String: Int64] = [:]
    var isLoadingApps = false
    var searchText = ""
    var sortOrder: AppSortOrder = .name
    var selection: SidebarItem?
    var hasFullDiskAccess = PermissionChecker.hasFullDiskAccess()
    var showOnboarding = false
    private var droppedIDs = Set<String>()

    var filteredApps: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var list = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
        switch sortOrder {
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: list.sort { (appSizes[$0.id] ?? 0) > (appSizes[$1.id] ?? 0) }
        }
        return list
    }

    func app(withID id: String) -> AppInfo? { apps.first { $0.id == id } }

    func loadApps() async {
        isLoadingApps = true
        let scanned = await Task.detached(priority: .userInitiated) { AppScanner.scanInstalledApps() }.value
        let extras = apps.filter { app in
            droppedIDs.contains(app.id) && !scanned.contains { $0.id == app.id } && FileManager.default.fileExists(atPath: app.url.path)
        }
        apps = scanned + extras
        isLoadingApps = false
        await loadSizes()
    }

    private func loadSizes() async {
        let pending = apps.filter { appSizes[$0.id] == nil }
        let sizes = await Task.detached(priority: .utility) {
            Parallel.map(pending) { ($0.id, FileSize.of($0.url)) }
        }.value
        for (id, size) in sizes { appSizes[id] = size }
    }

    /// Drag & drop, Dock drop and File ▸ Open all end up here.
    @discardableResult
    func open(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else { return false }
        let std = url.standardizedFileURL
        if let existing = apps.first(where: { $0.url.standardizedFileURL == std }) {
            selection = .app(existing.id)
            return true
        }
        guard let info = AppBundleReader.read(url) else { return false }
        apps.append(info)
        droppedIDs.insert(info.id)
        selection = .app(info.id)
        Task { await loadSizes() }
        return true
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose an application to uninstall")
        if panel.runModal() == .OK { open(panel.urls) }
    }

    func didRemove(_ app: AppInfo) {
        apps.removeAll { $0.id == app.id }
        appSizes[app.id] = nil
        droppedIDs.remove(app.id)
        selection = nil
    }

    func refreshPermissions() {
        hasFullDiskAccess = PermissionChecker.hasFullDiskAccess()
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(PermissionChecker.fullDiskAccessSettingsURL)
    }
}

/// Small cache so list scrolling doesn't hit NSWorkspace repeatedly.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(for url: URL) -> NSImage {
        if let img = cache[url.path] { return img }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = img
        return img
    }
}

extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
