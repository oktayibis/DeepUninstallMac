import AppKit
import DeepUninstallCore
import SwiftUI

extension LeftoverCategory {
    var title: String {
        switch self {
        case .application: String(localized: "Application")
        case .applicationSupport: String(localized: "Application Support")
        case .caches: String(localized: "Caches")
        case .preferences: String(localized: "Preferences")
        case .containers: String(localized: "Containers")
        case .savedState: String(localized: "Saved State")
        case .webData: String(localized: "Web Data & Cookies")
        case .logs: String(localized: "Logs & Crash Reports")
        case .launchItems: String(localized: "Launch Agents & Daemons")
        case .extensions: String(localized: "Plug-ins & Extensions")
        case .receipts: String(localized: "Installer Receipts")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .application: "app"
        case .applicationSupport: "folder"
        case .caches: "internaldrive"
        case .preferences: "slider.horizontal.3"
        case .containers: "shippingbox"
        case .savedState: "rectangle.stack"
        case .webData: "globe"
        case .logs: "doc.text"
        case .launchItems: "gearshape.2"
        case .extensions: "puzzlepiece.extension"
        case .receipts: "doc.badge.gearshape"
        case .other: "ellipsis.circle"
        }
    }
}

/// One file/folder with a checkbox.
struct LeftoverRow: View {
    let item: LeftoverItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isSelected).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: IconCache.icon(for: item.url))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text(item.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.confidence == .low {
                Text("Uncertain")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .help(Text("Weak match by name. Review before removing."))
            }
            if item.requiresAdmin {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(Text("Requires administrator password"))
            }
            Text(item.size.formattedBytes)
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help(Text("Show in Finder"))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }
}

/// Bottom action bar shared by app & orphan screens.
struct ActionBar: View {
    let selectedCount: Int
    let totalCount: Int
    let selectedBytes: Int64
    let buttonTitle: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) of \(totalCount) selected").font(.callout)
                Text(selectedBytes.formattedBytes).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Spacer()
            if isWorking { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button(role: .destructive, action: action) {
                Text(buttonTitle).frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(selectedCount == 0 || isWorking)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct SummaryView: View {
    let result: RemovalResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            Text(result.mode == .trash ? "Moved to Trash" : "Permanently Deleted")
                .font(.title2.weight(.semibold))
            Text("\(result.removed.count) items removed · \(result.freedBytes.formattedBytes) freed")
                .foregroundStyle(.secondary)
            if result.skippedAdmin > 0 {
                Text("\(result.skippedAdmin) items requiring administrator privileges were skipped.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !result.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Could not remove:").font(.callout.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.failures, id: \.self) { failure in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(failure.url.abbreviatedPath).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Text(failure.message).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(28)
        .frame(width: 440)
    }
}
