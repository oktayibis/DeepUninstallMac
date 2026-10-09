import DeepUninstallCore
import SwiftUI

struct LeftoverDetailView: View {
    let app: AppInfo
    let model: AppModel

    @State private var items: [LeftoverItem] = []
    @State private var selected = Set<String>()
    @State private var isScanning = true
    @State private var isRemoving = false
    @State private var result: RemovalResult?

    private var selectedItems: [LeftoverItem] { items.filter { selected.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var groups: [(LeftoverCategory, [LeftoverItem])] {
        Dictionary(grouping: items, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isScanning {
                ProgressView("Scanning for leftovers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
            Divider()
            ActionBar(
                selectedCount: selected.count, totalCount: items.count, selectedBytes: selectedBytes,
                buttonTitle: String(localized: "Uninstall"), isWorking: isRemoving, action: uninstall
            )
        }
        .task(id: app.id) { await scan() }
        .sheet(item: $result) { result in
            SummaryView(result: result) {
                let appRemoved = result.removed.contains { $0.standardizedFileURL == app.url.standardizedFileURL }
                self.result = nil
                if appRemoved { model.didRemove(app) } else { Task { await scan() } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if let version = app.version { Text("Version \(version)") }
                    if let bundleID = app.bundleID { Text(bundleID).textSelection(.enabled) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(app.url.abbreviatedPath)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !isScanning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(items.reduce(0) { $0 + $1.size }.formattedBytes)
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("\(items.count) items found").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.0) { category, categoryItems in
                Section {
                    ForEach(categoryItems) { item in
                        LeftoverRow(item: item, isSelected: binding(for: item.id))
                    }
                } header: {
                    CategoryHeader(category: category, items: categoryItems, selected: $selected)
                }
            }
        }
        .listStyle(.inset)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { if $0 { selected.insert(id) } else { selected.remove(id) } }
        )
    }

    private func scan() async {
        isScanning = true
        let target = app
        let installed = model.apps
        let found = await Task.detached(priority: .userInitiated) {
            LeftoverFinder.find(for: target, installedApps: installed)
        }.value
        items = found
        selected = Set(found.filter(\.selectedByDefault).map(\.id))
        isScanning = false
    }

    private func uninstall() {
        Task {
            isRemoving = true
            defer { isRemoving = false }
            if let r = await UninstallWorkflow.run(items: selectedItems, appName: app.name, bundleID: app.bundleID) {
                result = r
            }
        }
    }
}

struct CategoryHeader: View {
    let category: LeftoverCategory
    let items: [LeftoverItem]
    @Binding var selected: Set<String>

    private var allSelected: Bool { items.allSatisfy { selected.contains($0.id) } }

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { on in
                    for item in items { if on { selected.insert(item.id) } else { selected.remove(item.id) } }
                }
            )) {
                Label(category.title, systemImage: category.symbol)
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(items.reduce(0) { $0 + $1.size }.formattedBytes).monospacedDigit()
        }
    }
}
