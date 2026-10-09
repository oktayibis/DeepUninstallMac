import AppKit
import DeepUninstallCore
import SwiftUI

/// Leftovers of apps that are already gone (deleted by dragging to the Trash, etc.).
struct OrphansView: View {
    let model: AppModel

    @State private var groups: [OrphanGroup] = []
    @State private var selected = Set<String>()
    @State private var expanded = Set<String>()
    @State private var isScanning = true
    @State private var isRemoving = false
    @State private var result: RemovalResult?

    private var allItems: [LeftoverItem] { groups.flatMap(\.items) }
    private var selectedItems: [LeftoverItem] { allItems.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "questionmark.folder.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Orphaned Files").font(.title2.weight(.semibold))
                    Text("Files left behind by apps that are no longer installed. Nothing is selected by default – review carefully.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }
            .padding(20)
            Divider()

            if isScanning {
                ProgressView("Looking for orphaned files…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView("No orphaned files found", systemImage: "sparkles",
                                       description: Text("Your Library looks clean."))
            } else {
                List {
                    ForEach(groups) { group in
                        DisclosureGroup(isExpanded: expandedBinding(group.key)) {
                            ForEach(group.items) { item in
                                LeftoverRow(item: item, isSelected: itemBinding(item.id))
                            }
                        } label: {
                            groupLabel(group)
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            ActionBar(
                selectedCount: selected.count, totalCount: allItems.count,
                selectedBytes: selectedItems.reduce(0) { $0 + $1.size },
                buttonTitle: String(localized: "Remove"), isWorking: isRemoving, action: remove
            )
        }
        .task { await scan() }
        .sheet(item: $result) { result in
            SummaryView(result: result) {
                self.result = nil
                Task { await scan() }
            }
        }
    }

    private func groupLabel(_ group: OrphanGroup) -> some View {
        HStack {
            Toggle(isOn: groupBinding(group)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.key).font(.body.monospaced())
                    Text("\(group.items.count) items").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            if group.vendorHasInstalledApps {
                Label("Vendor app installed", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(Text("Another app from this developer is still installed and may use these files."))
            }
            Text(group.totalSize.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func groupBinding(_ group: OrphanGroup) -> Binding<Bool> {
        Binding(
            get: { group.items.allSatisfy { selected.contains($0.id) } },
            set: { on in group.items.forEach { if on { selected.insert($0.id) } else { selected.remove($0.id) } } }
        )
    }

    private func itemBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }

    private func expandedBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) }, set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    private func scan() async {
        isScanning = true
        if model.apps.isEmpty { await model.loadApps() }
        let installed = model.apps
        groups = await Task.detached(priority: .userInitiated) {
            OrphanFinder.find(installedApps: installed, isRegisteredBundleID: { bundleID in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            })
        }.value
        selected = []
        isScanning = false
    }

    private func remove() {
        Task {
            isRemoving = true
            defer { isRemoving = false }
            if let r = await UninstallWorkflow.run(items: selectedItems, appName: nil, bundleID: nil) {
                result = r
            }
        }
    }
}
