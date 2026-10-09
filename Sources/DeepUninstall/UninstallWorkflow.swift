import AppKit
import DeepUninstallCore

/// The step-by-step confirmation flow before anything is deleted:
/// 1. Trash or permanent?  2. Include admin-only items?  3. Quit the running app?
@MainActor
enum UninstallWorkflow {
    static func run(items: [LeftoverItem], appName: String?, bundleID: String?) async -> RemovalResult? {
        guard !items.isEmpty else { return nil }

        // 1. Removal mode – always asked.
        let total = items.reduce(0) { $0 + $1.size }.formattedBytes
        let modeAlert = NSAlert()
        modeAlert.alertStyle = .warning
        modeAlert.messageText = String(localized: "Remove \(items.count) items (\(total))?")
        modeAlert.informativeText = String(localized: "Items moved to the Trash can be restored until you empty it. Permanently deleted items cannot be recovered.")
        modeAlert.addButton(withTitle: String(localized: "Move to Trash"))
        let permanent = modeAlert.addButton(withTitle: String(localized: "Delete Permanently"))
        permanent.hasDestructiveAction = true
        modeAlert.addButton(withTitle: String(localized: "Cancel"))

        let mode: RemovalMode
        switch modeAlert.runModal() {
        case .alertFirstButtonReturn: mode = .trash
        case .alertSecondButtonReturn: mode = .permanent
        default: return nil
        }

        // 2. Items in system locations need the admin password.
        var allowAdmin = false
        let adminCount = items.filter(\.requiresAdmin).count
        if adminCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "\(adminCount) items require administrator privileges")
            alert.informativeText = String(localized: "These files are in system locations such as /Library. Include them? You will be asked for your password once.")
            alert.addButton(withTitle: String(localized: "Include"))
            alert.addButton(withTitle: String(localized: "Skip These Items"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: allowAdmin = true
            case .alertSecondButtonReturn: allowAdmin = false
            default: return nil
            }
        }

        // 3. The app must not be running while its bundle is removed.
        if let bundleID, items.contains(where: { $0.category == .application }) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if !running.isEmpty {
                let alert = NSAlert()
                alert.messageText = String(localized: "\(appName ?? bundleID) is running")
                alert.informativeText = String(localized: "The application will be quit before it is removed.")
                alert.addButton(withTitle: String(localized: "Quit and Continue"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }

                running.forEach { $0.terminate() }
                for _ in 0..<50 where !running.allSatisfy(\.isTerminated) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            }
        }

        return await Remover.remove(items, mode: mode, allowAdmin: allowAdmin)
    }
}
