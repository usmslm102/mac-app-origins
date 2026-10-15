import SwiftUI

struct ScanActivityView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ActivityFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(24)

            if let comparison = viewModel.scanComparison, comparison.hasBaseline {
                comparisonContent(comparison)
            } else {
                baselineContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 540, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Scan Activity")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(comparisonDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var comparisonDescription: String {
        guard let comparison = viewModel.scanComparison else {
            return "See what changes between scans. Your previous scan is saved on this Mac."
        }
        let current = comparison.currentDate.formatted(date: .abbreviated, time: .shortened)
        guard comparison.hasBaseline, let previous = comparison.previousDate else {
            return "Baseline captured \(current)."
        }
        return "\(previous.formatted(date: .abbreviated, time: .shortened)) → \(current)"
    }

    private func comparisonContent(_ comparison: ScanComparison) -> some View {
        let changes = filteredChanges(in: comparison)
        return VStack(spacing: 0) {
            HStack(spacing: 28) {
                activityCount(comparison, kind: .added, title: "Added", symbol: "plus.circle", color: .green)
                activityCount(comparison, kind: .changed, title: "Changed", symbol: "arrow.triangle.2.circlepath", color: .orange)
                activityCount(comparison, kind: .removed, title: "No longer found", symbol: "minus.circle", color: .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            if !comparison.changes.isEmpty {
                HStack(spacing: 16) {
                    Picker("Activity type", selection: $filter) {
                        ForEach(ActivityFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)

                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Search activity", text: $searchText)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Search activity by name or path")
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear activity search")
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider()

            if comparison.changes.isEmpty {
                emptyState(
                    symbol: "checkmark.circle",
                    title: "No changes found",
                    message: "Names, versions, sources and signing details match your previous scan."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if changes.isEmpty {
                VStack(spacing: 16) {
                    emptyState(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "No matching activity",
                        message: "Try another activity type or search for a different name or path."
                    )
                    Button("Clear Filters") {
                        filter = .all
                        searchText = ""
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(changes) { change in
                            activityRow(change)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    private func activityCount(_ comparison: ScanComparison, kind: ScanChange.Kind, title: String, symbol: String, color: Color) -> some View {
        let count = comparison.changes.lazy.filter { $0.kind == kind }.count
        return HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(count, format: .number)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(title.lowercased())")
    }

    private func activityRow(_ change: ScanChange) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: change.app.kind == .application ? "app" : "terminal")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(change.app.name)
                        .font(.headline)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    statusLabel(change.kind)
                    Spacer(minLength: 8)
                    if change.current != nil {
                        Button("Show Item") {
                            viewModel.selectActivityApp(path: change.app.path)
                            dismiss()
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Show \(change.app.name) in the app list")
                    }
                }

                Text(change.app.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(change.app.path)

                if let previous = change.previous, let current = change.current {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(change.changedFields, id: \.self) { field in
                            changedField(field, previous: previous, current: current)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 16) {
                        itemFact("Version", value: change.app.version)
                        itemFact("Source", value: change.app.source.rawValue)
                        itemFact("Signing", value: change.app.securityStatus.rawValue)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusLabel(_ kind: ScanChange.Kind) -> some View {
        let title: String
        let color: Color
        switch kind {
        case .added:
            title = "Added"
            color = .green
        case .changed:
            title = "Changed"
            color = .orange
        case .removed:
            title = "No longer found"
            color = .secondary
        }
        return Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }

    private func changedField(_ field: ScanChange.Field, previous: ScanSnapshotItem, current: ScanSnapshotItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(field == .securityStatus ? "Signing" : field.label)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value(for: field, in: previous))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .accessibilityLabel("changed to")
            Text(value(for: field, in: current))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func itemFact(_ title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "Unknown" : value)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var baselineContent: some View {
        if let comparison = viewModel.scanComparison {
            if comparison.state == .scopeChanged {
                emptyState(
                    symbol: "folder.badge.gearshape",
                    title: "Scan scope changed",
                    message: "A new baseline was saved for your selected locations. The next scan with the same scope will show what changed."
                )
            } else {
                emptyState(
                    symbol: "clock.badge.checkmark",
                    title: "Your baseline is saved",
                    message: "Refresh after adding or updating software to see what changed. Your baseline is kept when you close AppOrigins."
                )
            }
        } else if viewModel.isLoading {
            VStack(spacing: 14) {
                ProgressView()
                Text("Scanning applications…")
                    .foregroundStyle(.secondary)
            }
        } else {
            emptyState(
                symbol: "clock.arrow.circlepath",
                title: "Your activity starts with a scan",
                message: "Complete a scan to save your baseline. Future scans will highlight added items and changes to their details."
            )
        }
    }

    private func emptyState(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .padding(24)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("“No longer found” can include disconnected volumes or items moved to another location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.exportScanActivity()
            } label: {
                Label("Export JSON…", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.scanComparison == nil)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func filteredChanges(in comparison: ScanComparison) -> [ScanChange] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return comparison.changes.filter { change in
            let matchesType = filter.kind.map { $0 == change.kind } ?? true
            let matchesSearch = query.isEmpty
                || change.app.name.localizedCaseInsensitiveContains(query)
                || change.app.path.localizedCaseInsensitiveContains(query)
            return matchesType && matchesSearch
        }
    }

    private func value(for field: ScanChange.Field, in item: ScanSnapshotItem) -> String {
        let value: String
        switch field {
        case .name: value = item.name
        case .kind: value = item.kind.rawValue
        case .bundleIdentifier: value = item.bundleIdentifier
        case .version: value = item.version
        case .securityStatus: value = item.securityStatus.rawValue
        case .source: value = item.source.rawValue
        }
        return value.isEmpty ? "Unknown" : value
    }
}

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case added = "Added"
    case changed = "Changed"
    case removed = "No longer found"

    var id: Self { self }

    var kind: ScanChange.Kind? {
        switch self {
        case .all: nil
        case .added: .added
        case .changed: .changed
        case .removed: .removed
        }
    }
}
