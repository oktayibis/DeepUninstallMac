import DeepUninstallCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false
    @AppStorage("onboardingDismissed") private var onboardingDismissed = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 400)
        } detail: {
            detail
        }
        .overlay {
            if isDropTargeted { DropOverlay() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
        } isTargeted: { isDropTargeted = $0 }
        .task {
            if !model.hasFullDiskAccess && !onboardingDismissed { model.showOnboarding = true }
            await model.loadApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model) { onboardingDismissed = true }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .app(let id):
            if let app = model.app(withID: id) {
                LeftoverDetailView(app: app, model: model).id(id)
            } else {
                WelcomeView(model: model)
            }
        case .orphans:
            OrphansView(model: model)
        case nil:
            WelcomeView(model: model)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                Label("Orphaned Files", systemImage: "questionmark.folder")
                    .tag(SidebarItem.orphans)
            }
            Section {
                ForEach(model.filteredApps) { app in
                    AppRow(app: app, size: model.appSizes[app.id])
                        .tag(SidebarItem.app(app.id))
                }
            } header: {
                Text("Applications (\(model.filteredApps.count))")
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: Text("Search apps"))
        .overlay {
            if model.isLoadingApps && model.apps.isEmpty { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.hasFullDiskAccess { PermissionBanner(model: model) }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker(selection: $model.sortOrder) {
                    ForEach(AppSortOrder.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
                .help(Text("Sort applications"))

                Button {
                    Task { await model.loadApps() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help(Text("Reload applications"))
            }
        }
    }
}

struct AppRow: View {
    let app: AppInfo
    let size: Int64?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                if let version = app.version {
                    Text(version).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let size {
                Text(size.formattedBytes).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PermissionBanner: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Full Disk Access is off", systemImage: "exclamationmark.shield")
                .font(.callout.weight(.semibold))
            Text("Some leftovers can't be found without it.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Grant Access…") { model.showOnboarding = true }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }
}

// MARK: - Welcome / drop

struct WelcomeView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.tertiary)
                    .frame(width: 220, height: 160)
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("Drop an app here")
                .font(.title2.weight(.semibold))
            Text("or select one from the list to find everything it left behind.")
                .foregroundStyle(.secondary)
            Button("Choose Application…") { model.showOpenPanel() }
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Drop to scan for leftovers").font(.title3.weight(.medium))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3).padding(6))
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let model: AppModel
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Allow Full Disk Access")
                .font(.title2.weight(.semibold))
            Text("Apps store data in protected folders such as ~/Library/Containers. DeepUninstall needs Full Disk Access to find and remove them. Nothing is ever deleted without your confirmation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Open System Settings ▸ Privacy & Security ▸ Full Disk Access", systemImage: "1.circle")
                Label("Turn on DeepUninstall (use + to add it if missing)", systemImage: "2.circle")
                Label("Come back here – access is detected automatically", systemImage: "3.circle")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if model.hasFullDiskAccess {
                Label("Full Disk Access granted", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Continue Without") { onDismiss(); dismiss() }
                Spacer()
                if model.hasFullDiskAccess {
                    Button("Done") { onDismiss(); dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 500)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            model.refreshPermissions()
        }
    }
}
