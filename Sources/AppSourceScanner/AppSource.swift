import AppKit
import Foundation

enum AppSource: String, CaseIterable, Codable, Sendable {
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case manual = "Manual / Unknown"
}

enum InstallKind: String, CaseIterable, Codable, Sendable {
    case application = "Application"
    case cliTool = "CLI Tool"
}

struct ScannedApp: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: InstallKind
    let bundleIdentifier: String
    let version: String
    let sizeInBytes: Int64?
    let path: String
    let source: AppSource

    init(name: String, kind: InstallKind, bundleIdentifier: String, version: String, sizeInBytes: Int64?, path: String, source: AppSource) {
        self.id = path
        self.name = name
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sizeInBytes = sizeInBytes
        self.path = path
        self.source = source
    }
}

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let kind: InstallKind
    let bundleIdentifier: String
    let version: String
    let sizeInBytes: Int64?
    let path: String
    let source: AppSource
    let icon: NSImage

    init(name: String, kind: InstallKind, bundleIdentifier: String, version: String, sizeInBytes: Int64?, path: String, source: AppSource, icon: NSImage) {
        self.id = path
        self.name = name
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sizeInBytes = sizeInBytes
        self.path = path
        self.source = source
        self.icon = icon
    }

    init(scannedApp: ScannedApp, icon: NSImage) {
        self.id = scannedApp.id
        self.name = scannedApp.name
        self.kind = scannedApp.kind
        self.bundleIdentifier = scannedApp.bundleIdentifier
        self.version = scannedApp.version
        self.sizeInBytes = scannedApp.sizeInBytes
        self.path = scannedApp.path
        self.source = scannedApp.source
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
}

enum SourceFilter: String, CaseIterable, Identifiable {
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
    let size: String
    let sizeInBytes: Int64?
    let path: String
    let source: String

    init(app: InstalledApp) {
        name = app.name
        kind = app.kind.rawValue
        bundleIdentifier = app.bundleIdentifier
        version = app.version
        size = app.sizeLabel
        sizeInBytes = app.sizeInBytes
        path = app.path
        source = app.source.rawValue
    }
}
