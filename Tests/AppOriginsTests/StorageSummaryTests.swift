import Foundation
import Testing
@testable import AppOrigins

struct StorageSummaryTests {
    @Test func aggregatesEveryInstallationBySourceKindAndLocation() {
        let summary = StorageSummary(apps: [
            item("tool", kind: .cliTool, source: .homebrew, size: 100),
            item("Brew App", source: .homebrew, size: 200),
            item("Example", source: .appStore, size: 300),
            item("Example Copy", source: .manual, size: 400, external: true, identifier: "test.Example"),
            item("Unreadable", source: .manual, size: nil, external: true),
            item("empty-tool", kind: .cliTool, source: .homebrew, size: 0, external: true)
        ])

        expect(summary.total, count: 6, bytes: 1_000, unknown: 1)
        #expect(summary.bySource.map(\.source) == AppSource.allCases)
        #expect(summary.bySource.map(\.id) == AppSource.allCases)
        expect(summary.bySource[0].total, count: 3, bytes: 300)
        expect(summary.bySource[1].total, count: 1, bytes: 300)
        expect(summary.bySource[2].total, count: 2, bytes: 400, unknown: 1)
        expect(summary.applications, count: 4, bytes: 900, unknown: 1)
        expect(summary.cliTools, count: 2, bytes: 100)
        expect(summary.internalStorage, count: 3, bytes: 600)
        expect(summary.externalStorage, count: 3, bytes: 400, unknown: 1)
    }

    @Test func distinguishesUnknownSizesFromMeasuredZero() {
        let unknown = StorageSummary(apps: [item("Unreadable", size: nil)]).total
        expect(unknown, count: 1, bytes: 0, unknown: 1)
        #expect(unknown.sizeLabel == "Unknown")

        let zero = StorageSummary(apps: [item("Empty", size: 0)]).total
        expect(zero, count: 1, bytes: 0)
        #expect(zero.sizeLabel == ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))

        let partial = StorageSummary(apps: [item("Unreadable", size: nil), item("Empty", size: 0)]).total
        expect(partial, count: 2, bytes: 0, unknown: 1)
        #expect(partial.sizeLabel == zero.sizeLabel)
    }

    @Test func emptyInventoryHasZeroTotalsForEveryCategory() {
        let summary = StorageSummary(apps: [])
        let totals = [summary.total, summary.applications, summary.cliTools, summary.internalStorage, summary.externalStorage]
            + summary.bySource.map(\.total)

        #expect(summary.bySource.map(\.source) == AppSource.allCases)
        for total in totals {
            expect(total, count: 0, bytes: 0)
            #expect(total.sizeLabel == ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
        }
    }

    private func expect(_ total: StorageSizeTotal, count: Int, bytes: Int64, unknown: Int = 0) {
        #expect(total.itemCount == count)
        #expect(total.sizeInBytes == bytes)
        #expect(total.unknownSizeCount == unknown)
        #expect(total.knownSizeCount == count - unknown)
    }

    private func item(
        _ name: String,
        kind: InstallKind = .application,
        source: AppSource = .manual,
        size: Int64?,
        external: Bool = false,
        identifier: String? = nil
    ) -> ScannedApp {
        ScannedApp(
            name: name, kind: kind, bundleIdentifier: identifier ?? "test.\(name)",
            version: "1.0", securityStatus: .signed, sizeInBytes: size,
            path: "\(external ? "/Volumes/External" : "")/Applications/\(name)", source: source,
            location: external ? "External" : "Internal Disk", isExternal: external
        )
    }
}
