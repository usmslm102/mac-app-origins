import Foundation
import Testing
@testable import AppOrigins

struct ScanActivityTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let scope = ScanScope(
        includeSystemApplications: true,
        includeUserApplications: true,
        includeExternalVolumes: false
    )

    @Test func tracksAddedRemovedAndAllMetadataChangesTogether() throws {
        let before = snapshot([
            app("Removed", path: "/Applications/Removed.app"),
            app("Editor", path: "/Applications/Editor.app", version: "1.0", security: .unsigned, source: .manual),
            app("Unchanged", path: "/Applications/Unchanged.app")
        ])
        let after = snapshot([
            app("Added", path: "/Applications/Added.app"),
            app("Editor", path: "/Applications/Editor.app", version: "2.0", security: .signed, source: .homebrew),
            app("Unchanged", path: "/Applications/Unchanged.app")
        ], offset: 60)

        let comparison = ScanComparison(previous: before, current: after)

        #expect(comparison.state == .compared)
        #expect(comparison.hasBaseline)
        #expect(comparison.previousDate == before.date)
        #expect(comparison.currentDate == after.date)
        #expect(comparison.changes.map(\.kind) == [.added, .changed, .removed])
        let changed = try #require(comparison.changes.first { $0.kind == .changed })
        #expect(changed.changedFields == [.version, .securityStatus, .source])
        #expect(changed.previous?.version == "1.0")
        #expect(changed.current?.version == "2.0")
        #expect(changed.detail.contains("Version: 1.0 → 2.0"))
        #expect(changed.detail.contains("Security: Unsigned → Signed"))
        #expect(changed.detail.contains("Source: Manual / Unknown → Homebrew"))
        #expect(comparison.changes.first?.previous == nil)
        #expect(comparison.changes.last?.current == nil)
    }

    @Test func sizeChangesDoNotCreateActivity() {
        let before = snapshot([app("Editor", path: "/Applications/Editor.app", size: 1_024)])
        let after = snapshot([app("Editor", path: "/Applications/Editor.app", size: 8_192)], offset: 60)

        #expect(before.items == after.items)
        #expect(ScanComparison(previous: before, current: after).changes.isEmpty)
    }

    @Test func initialScanEstablishesBaseline() {
        let comparison = ScanComparison(previous: nil, current: snapshot([app("Editor")]))

        #expect(comparison.state == .initialBaseline)
        #expect(!comparison.hasBaseline)
        #expect(comparison.previousDate == nil)
        #expect(comparison.changes.isEmpty)
    }

    @Test(arguments: [
        ScanScope(includeSystemApplications: false, includeUserApplications: true, includeExternalVolumes: false),
        ScanScope(includeSystemApplications: true, includeUserApplications: false, includeExternalVolumes: false),
        ScanScope(includeSystemApplications: true, includeUserApplications: true, includeExternalVolumes: true)
    ])
    func scopeChangesEstablishNewBaseline(changedScope: ScanScope) {
        let before = snapshot([app("Editor")])
        let after = ScanSnapshot(apps: [app("Other")], scope: changedScope, date: date.addingTimeInterval(60))
        let comparison = ScanComparison(previous: before, current: after)

        #expect(comparison.state == .scopeChanged)
        #expect(!comparison.hasBaseline)
        #expect(comparison.scope == changedScope)
        #expect(comparison.changes.isEmpty)
    }

    @Test func duplicateCopiesAreMatchedByPathInsteadOfBundleIdentifier() throws {
        let before = snapshot([
            app("Editor", path: "/Applications/Editor.app", identifier: "com.example.editor"),
            app("Editor", path: "/Volumes/Backup/Editor.app", identifier: "com.example.editor")
        ])
        let after = snapshot([
            app("Editor", path: "/Applications/Editor.app", identifier: "com.example.editor", version: "2.0")
        ])
        let comparison = ScanComparison(previous: before, current: after)

        #expect(comparison.changes.count == 2)
        let changed = try #require(comparison.changes.first { $0.kind == .changed })
        let removed = try #require(comparison.changes.first { $0.kind == .removed })
        #expect(changed.id == "/Applications/Editor.app")
        #expect(removed.id == "/Volumes/Backup/Editor.app")
    }

    @Test func orderingIsStableAndRepeatedPathsAreCoalesced() {
        let apps = [
            app("Zulu", path: "/Applications/Zulu.app"),
            app("alpha", path: "/Volumes/Backup/alpha.app"),
            app("Alpha", path: "/Applications/Alpha.app", version: "2.0"),
            app("Alpha", path: "/Applications/Alpha.app", version: "1.0")
        ]
        let forward = snapshot(apps)
        let reverse = snapshot(Array(apps.reversed()))
        let baseline = snapshot([])

        #expect(forward == reverse)
        #expect(forward.items.count == 3)
        #expect(forward.items.map(\.path) == [
            "/Applications/Alpha.app", "/Volumes/Backup/alpha.app", "/Applications/Zulu.app"
        ])
        #expect(ScanComparison(previous: baseline, current: forward) == ScanComparison(previous: baseline, current: reverse))
        #expect(ScanComparison(previous: baseline, current: forward).changes.map(\.id) == forward.items.map(\.id))
    }

    @Test func snapshotsAndComparisonsRoundTripThroughJSON() throws {
        let before = snapshot([app("Editor", version: "1.0"), app("Removed")])
        let after = snapshot([app("Editor", version: "2.0"), app("Added")], offset: 60)
        let comparison = ScanComparison(previous: before, current: after)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        #expect(try decoder.decode(ScanSnapshot.self, from: encoder.encode(after)) == after)
        #expect(try decoder.decode(ScanComparison.self, from: encoder.encode(comparison)) == comparison)
    }

    @Test func malformedChangeWithoutAnAppIsRejected() {
        let data = Data(#"{"kind":"added"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScanChange.self, from: data)
        }
    }

    private func snapshot(_ apps: [ScannedApp], offset: TimeInterval = 0) -> ScanSnapshot {
        ScanSnapshot(apps: apps, scope: scope, date: date.addingTimeInterval(offset))
    }

    private func app(
        _ name: String,
        path: String? = nil,
        identifier: String = "com.example.app",
        version: String = "1.0",
        security: SecurityStatus = .signed,
        source: AppSource = .manual,
        size: Int64? = 1_024
    ) -> ScannedApp {
        ScannedApp(
            name: name,
            kind: .application,
            bundleIdentifier: identifier,
            version: version,
            securityStatus: security,
            sizeInBytes: size,
            path: path ?? "/Applications/\(name).app",
            source: source,
            location: "Applications",
            isExternal: false
        )
    }
}
