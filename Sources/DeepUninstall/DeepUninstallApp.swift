import AppKit
import SwiftUI

@main
struct DeepUninstallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("DeepUninstall", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 540)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Application…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Reload Applications") { Task { await model.loadApps() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Apps dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
