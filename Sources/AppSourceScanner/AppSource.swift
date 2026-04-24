import AppKit
import Foundation

enum AppSource: String, CaseIterable, Codable, Sendable {
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case manual = "Manual / Unknown"
}

enum SourceTab: String, CaseIterable, Identifiable {
    case all = "All"
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case manual = "Manual"

    var id: Self { self }

    var source: AppSource? {
        switch self {
        case .all:
            return nil
        case .homebrew:
            return .homebrew
        case .appStore:
            return .appStore
        case .manual:
            return .manual
        }
    }
}

enum InstallKind: String, CaseIterable, Codable, Sendable {
    case application = "Application"
    case cliTool = "CLI Tool"
}

enum SecurityStatus: String, CaseIterable, Codable, Sendable {
    case appStore = "App Store"
    case signed = "Signed"
    case adHoc = "Ad Hoc"
    case unsigned = "Unsigned"
    case notApplicable = "Not Applicable"
}

enum SecurityFilter: String, CaseIterable, Identifiable {
    case all = "All Security"
    case trusted = "Trusted"
    case needsReview = "Needs Review"
    case appStore = "App Store"
    case signed = "Signed"
    case adHoc = "Ad Hoc"
    case unsigned = "Unsigned"

    var id: Self { self }

    func matches(_ status: SecurityStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .trusted:
            return status == .appStore || status == .signed
        case .needsReview:
            return status == .adHoc || status == .unsigned
        case .appStore:
            return status == .appStore
        case .signed:
            return status == .signed
        case .adHoc:
            return status == .adHoc
        case .unsigned:
            return status == .unsigned
        }
    }
}

struct ScannedApp: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: InstallKind
    let bundleIdentifier: String
    let version: String
    let securityStatus: SecurityStatus
    let sizeInBytes: Int64?
    let path: String
    let source: AppSource
    let location: String
    let isExternal: Bool

    init(name: String, kind: InstallKind, bundleIdentifier: String, version: String, securityStatus: SecurityStatus, sizeInBytes: Int64?, path: String, source: AppSource, location: String, isExternal: Bool) {
        self.id = path
        self.name = name
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.securityStatus = securityStatus
        self.sizeInBytes = sizeInBytes
        self.path = path
        self.source = source
        self.location = location
        self.isExternal = isExternal
    }
}

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let kind: InstallKind
    let bundleIdentifier: String
    let version: String
    let duplicateCount: Int
    let securityStatus: SecurityStatus
    let sizeInBytes: Int64?
    let path: String
    let source: AppSource
    let location: String
    let isExternal: Bool
    let icon: NSImage

    init(name: String, kind: InstallKind, bundleIdentifier: String, version: String, duplicateCount: Int = 1, securityStatus: SecurityStatus, sizeInBytes: Int64?, path: String, source: AppSource, location: String, isExternal: Bool, icon: NSImage) {
        self.id = path
        self.name = name
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.duplicateCount = duplicateCount
        self.securityStatus = securityStatus
        self.sizeInBytes = sizeInBytes
        self.path = path
        self.source = source
        self.location = location
        self.isExternal = isExternal
        self.icon = icon
    }

    init(scannedApp: ScannedApp, icon: NSImage) {
        self.id = scannedApp.id
        self.name = scannedApp.name
        self.kind = scannedApp.kind
        self.bundleIdentifier = scannedApp.bundleIdentifier
        self.version = scannedApp.version
        self.duplicateCount = 1
        self.securityStatus = scannedApp.securityStatus
        self.sizeInBytes = scannedApp.sizeInBytes
        self.path = scannedApp.path
        self.source = scannedApp.source
        self.location = scannedApp.location
        self.isExternal = scannedApp.isExternal
        self.icon = icon
    }

    var identifierLabel: String {
        switch kind {
        case .application:
            return "Bundle ID"
        case .cliTool:
            return "Formula"
        }
    }

    var sizeLabel: String {
        guard let sizeInBytes else {
            return "Unknown"
        }

        return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var hasDuplicates: Bool {
        duplicateCount > 1
    }

    var duplicateLabel: String {
        hasDuplicates ? "\(duplicateCount)x" : ""
    }

    var typeLabel: String {
        kind.rawValue
    }

    var sourceLabel: String {
        source.rawValue
    }

    var locationLabel: String {
        location
    }

    var securityStatusLabel: String {
        securityStatus.rawValue
    }

    var sizeSortValue: Int64 {
        sizeInBytes ?? -1
    }

    func withDuplicateCount(_ duplicateCount: Int) -> InstalledApp {
        InstalledApp(
            name: name,
            kind: kind,
            bundleIdentifier: bundleIdentifier,
            version: version,
            duplicateCount: duplicateCount,
            securityStatus: securityStatus,
            sizeInBytes: sizeInBytes,
            path: path,
            source: source,
            location: location,
            isExternal: isExternal,
            icon: icon
        )
    }
}

enum KindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case applications = "Apps"
    case cliTools = "CLI"

    var id: Self { self }

    var kind: InstallKind? {
        switch self {
        case .all:
            return nil
        case .applications:
            return .application
        case .cliTools:
            return .cliTool
        }
    }
}

struct ExportedApp: Codable {
    let name: String
    let kind: String
    let bundleIdentifier: String
    let version: String
    let duplicateCount: Int
    let securityStatus: String
    let size: String
    let sizeInBytes: Int64?
    let path: String
    let source: String
    let location: String
    let isExternal: Bool

    init(app: InstalledApp) {
        name = app.name
        kind = app.kind.rawValue
        bundleIdentifier = app.bundleIdentifier
        version = app.version
        duplicateCount = app.duplicateCount
        securityStatus = app.securityStatus.rawValue
        size = app.sizeLabel
        sizeInBytes = app.sizeInBytes
        path = app.path
        source = app.source.rawValue
        location = app.location
        isExternal = app.isExternal
    }
}
