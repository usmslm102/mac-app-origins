import Foundation
import Testing
@testable import AppOrigins

struct ScannerTests {
    @Test func sourceMatchingUsesWholeWordsAndIgnoresEmptyTokens() {
        #expect(ScannerLogic.detectSource(appName: "Spark", brewApps: ["arc"], appStoreApps: [], hasAppStoreReceipt: false) == .manual)
        #expect(ScannerLogic.detectSource(appName: "Example", brewApps: ["---"], appStoreApps: [], hasAppStoreReceipt: false) == .manual)
        #expect(ScannerLogic.detectSource(appName: "...", brewApps: ["example"], appStoreApps: [], hasAppStoreReceipt: false) == .manual)
        #expect(ScannerLogic.detectSource(appName: "Visual Studio Code", brewApps: ["visual-studio-code"], appStoreApps: [], hasAppStoreReceipt: false) == .homebrew)
    }

    @Test func appStoreEvidenceTakesPrecedenceOverCaskNameMatches() {
        #expect(ScannerLogic.detectSource(appName: "Example", brewApps: ["example"], appStoreApps: [], hasAppStoreReceipt: true) == .appStore)
        #expect(ScannerLogic.detectSource(appName: "Example", brewApps: ["example"], appStoreApps: ["example"], hasAppStoreReceipt: false) == .appStore)
    }

    @Test func subprocessDrainsBothPipesBeforeWaitingForExit() throws {
        // The alarm makes a pipe deadlock fail the test instead of hanging it.
        let result = try #require(Shell.runDetailed("/usr/bin/perl", arguments: [
            "-e", "alarm 5; print STDOUT 'o' x 262144; print STDERR 'e' x 262144;"
        ]))

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput == String(repeating: "o", count: 262144))
        #expect(result.standardError == String(repeating: "e", count: 262144))
    }

    @Test func quickScanRefreshesMetadataAfterAnInPlaceUpdate() async throws {
        let fixture = try TemporaryApplication()
        defer { fixture.remove() }
        let scanner = AppScanner()
        let initial = await scanner.scanAppBundles([fixture.url], brewApps: [], appStoreApps: [], mode: .quick)
        #expect(initial.apps.first?.version == "1.0")

        let unchanged = await scanner.scanAppBundles([fixture.url], brewApps: [], appStoreApps: [], mode: .quick)
        #expect(unchanged.cacheHits == 1)

        let directoryDate = try fixture.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try fixture.writeInfo(version: "2.1", build: "345")
        if let directoryDate {
            try FileManager.default.setAttributes([.modificationDate: directoryDate], ofItemAtPath: fixture.url.path)
        }

        let updated = await scanner.scanAppBundles([fixture.url], brewApps: [], appStoreApps: [], mode: .quick)
        #expect(updated.cacheMisses == 1)
        #expect(updated.apps.first?.version == "2.1 (345)")
    }

    @Test func quickScanRefreshesSourceWhenPackageManagerInventoryChanges() async throws {
        let fixture = try TemporaryApplication()
        defer { fixture.remove() }
        let scanner = AppScanner()
        let initial = await scanner.scanAppBundles([fixture.url], brewApps: [], appStoreApps: [], mode: .quick)
        #expect(initial.apps.first?.source == .manual)

        let updated = await scanner.scanAppBundles([fixture.url], brewApps: ["cache-fixture"], appStoreApps: [], mode: .quick)
        #expect(updated.cacheMisses == 1)
        #expect(updated.apps.first?.source == .homebrew)
    }

    @Test func receiptIsDetectedWithoutSpotlightIndexing() async throws {
        let fixture = try TemporaryApplication()
        defer { fixture.remove() }
        let receiptURL = fixture.url.appendingPathComponent("Contents/_MASReceipt/receipt")
        try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("receipt fixture".utf8).write(to: receiptURL)

        let result = await AppScanner().scanAppBundles([fixture.url], brewApps: [], appStoreApps: [], mode: .quick)
        #expect(result.apps.first?.source == .appStore)
        #expect(result.apps.first?.securityStatus == .appStore)
    }
}

private struct TemporaryApplication {
    let root: URL
    let url: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppOriginsTests-\(UUID().uuidString)")
        url = root.appendingPathComponent("Cache Fixture.app")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try writeInfo(version: "1.0", build: "1.0")
    }

    func writeInfo(version: String, build: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "test.apporigins.fixture",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
